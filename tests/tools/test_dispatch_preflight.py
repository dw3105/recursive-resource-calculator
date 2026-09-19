"""Disposable-repository coverage for the dispatch preflight gate."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
TOOL = REPO / "tools" / "check_dispatch.py"


def git(directory: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args], cwd=directory, check=True, capture_output=True, text=True
    )
    return result.stdout.strip()


class DispatchPreflight(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.checkout = self.root / "checkout"
        self.checkout.mkdir()
        git(self.checkout, "init", "-q")
        git(self.checkout, "config", "user.email", "test@example.invalid")
        git(self.checkout, "config", "user.name", "test")
        (self.checkout / "existing.txt").write_text("existing\n", encoding="utf-8")
        (self.checkout / "tests").mkdir()
        (self.checkout / "tests" / "test_existing.py").write_text(
            "# disposable test\n", encoding="utf-8"
        )
        git(self.checkout, "add", ".")
        git(self.checkout, "commit", "-q", "-m", "base")
        self.base = git(self.checkout, "rev-parse", "HEAD")
        self.manifest = self.root / "lane.manifest"
        self.manifest.write_text("existing.txt\n!tests/test_new.py\n", encoding="utf-8")
        self.task = self.root / "task.md"
        self.task.write_text(self.task_text(), encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def task_text(self, command="python3 tests/test_existing.py"):
        fence = chr(96) * 3
        return (
            "# disposable task\n\n"
            + fence
            + "checks\n"
            + json.dumps(
                {
                    "name": "fixture",
                    "command": command,
                    "expect_exit": 0,
                    "expect_regex": "OK",
                    "timeout_s": 30,
                }
            )
            + "\n"
            + fence
            + "\n"
        )

    def run_tool(self, *extra, manifest=None, task=None, base=None, repo=None):
        command = [
            sys.executable,
            str(TOOL),
            "--repo",
            str(repo or self.checkout),
            "--manifest",
            str(manifest or self.manifest),
            "--state-root",
            str(self.root / "state"),
        ]
        if task is not False and (task or self.task):
            command.extend(["--task", str(task or self.task)])
        if base is not False and (base or self.base):
            command.extend(["--base", str(base or self.base)])
        command.extend(str(value) for value in extra)
        return subprocess.run(command, capture_output=True, text=True)

    def assert_refused(self, result, text):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(text, result.stdout)

    def descriptor(self, *, manifest: Path, worktree: Path, label="other-lane", task=None):
        path = self.root / (label + ".json")
        value = {
            "label": label,
            "running": True,
            "manifest": str(manifest),
            "worktree": str(worktree),
        }
        if task is not None:
            value["task"] = str(task)
        path.write_text(json.dumps(value) + "\n", encoding="utf-8")
        return path

    def test_valid_task_is_ready_and_new_deliverable_need_not_exist(self):
        result = self.run_tool()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("READY", result.stdout)
        self.assertIn(str(self.task), result.stdout)
        self.assertFalse((self.checkout / "tests" / "test_new.py").exists())

    def test_manifest_refuses_literal_newline_and_nul(self):
        cases = (
            (b"existing.txt\\nother.txt\n", "literal \\n bytes"),
            (b"existing.txt\x00\n", "NUL byte"),
        )
        for raw, expected in cases:
            with self.subTest(expected=expected):
                self.manifest.write_bytes(raw)
                self.assert_refused(self.run_tool(task=False, base=False), expected)

    def test_manifest_refuses_empty_duplicate_malformed_and_no_entries(self):
        cases = (
            ("existing.txt\n\n", "empty manifest entry"),
            ("existing.txt\nexisting.txt\n", "duplicate manifest entry"),
            ("!\n", "malformed empty manifest entry"),
            ("/absolute.txt\n", "manifest path is absolute"),
            ("../outside.txt\n", "manifest path escapes repository"),
            ("some\\path.txt\n", "manifest path carries a backslash"),
            ("# comment only\n", "manifest has no entries"),
        )
        for raw, expected in cases:
            with self.subTest(expected=expected):
                self.manifest.write_text(raw, encoding="utf-8")
                self.assert_refused(self.run_tool(task=False, base=False), expected)

    def test_missing_manifest_and_task_are_named(self):
        self.assert_refused(
            self.run_tool(manifest=self.root / "missing.manifest", task=False, base=False),
            "missing manifest",
        )
        self.assert_refused(
            self.run_tool(task=self.root / "missing.md"),
            "missing task file",
        )

    def test_base_must_resolve_and_worktree_must_stand_on_it(self):
        self.assert_refused(
            self.run_tool(base="does-not-exist"),
            "base does not resolve",
        )
        (self.checkout / "later.txt").write_text("later\n", encoding="utf-8")
        git(self.checkout, "add", "later.txt")
        git(self.checkout, "commit", "-q", "-m", "later")
        self.assert_refused(
            self.run_tool(base=self.base),
            "worktree stands at",
        )

    def test_checks_block_must_be_one_json_object_per_line(self):
        fence = chr(96) * 3
        invalid = (
            "no checks fence\n",
            fence + "checks\nnot json\n" + fence + "\n",
            fence + "checks\n[]\n" + fence + "\n",
            fence + "checks\n{}\n\n{}\n" + fence + "\n",
        )
        for text in invalid:
            with self.subTest(text=text):
                self.task.write_text(text, encoding="utf-8")
                result = self.run_tool()
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertRegex(result.stdout, r"checks|JSON object")

    def test_missing_named_test_is_refused_but_required_new_test_is_not(self):
        self.task.write_text(self.task_text("python3 tests/test_missing.py"), encoding="utf-8")
        self.assert_refused(self.run_tool(), "tests/test_missing.py")
        self.task.write_text(self.task_text("python3 tests/test_new.py"), encoding="utf-8")
        result = self.run_tool()
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_directory_against_file_ownership_clash_is_refused(self):
        (self.checkout / "tests" / "golden" / "lib").mkdir(parents=True)
        self.manifest.write_text("tests/golden/\n", encoding="utf-8")
        active_manifest = self.root / "active.manifest"
        active_manifest.write_text("tests/golden/lib/runner.py\n", encoding="utf-8")
        descriptor = self.descriptor(
            manifest=active_manifest, worktree=self.root / "active", label="lane-file"
        )
        result = self.run_tool("--running-lane", str(descriptor), task=False, base=False)
        self.assert_refused(result, "ownership clash")
        self.assertIn("tests/golden/", result.stdout)
        self.assertIn("tests/golden/lib/runner.py", result.stdout)

    def test_worktree_with_running_lane_is_refused(self):
        active_manifest = self.root / "active.manifest"
        active_manifest.write_text("unrelated.txt\n", encoding="utf-8")
        descriptor = self.descriptor(
            manifest=active_manifest, worktree=self.checkout, label="lane-here"
        )
        result = self.run_tool("--running-lane", str(descriptor), task=False, base=False)
        self.assert_refused(result, "worktree already holds a running lane")

    def test_live_audit_record_is_read_without_running_a_lane(self):
        active_task = self.checkout / "active.md"
        active_task.write_text("active\n", encoding="utf-8")
        (self.checkout / "active.manifest").write_text("unrelated.txt\n", encoding="utf-8")
        audit = self.checkout / "docs" / "audit" / "runs" / "active" / "attempts" / "one"
        audit.mkdir(parents=True)
        stat_fields = Path(f"/proc/{os.getpid()}/stat").read_text().split()
        starttime = int(stat_fields[21])
        (audit / "record.json").write_text(
            json.dumps(
                {
                    "label": "recorded-lane",
                    "state": "running",
                    "task": str(active_task),
                    "worktree": str(self.checkout),
                    "worker": {"pid": os.getpid(), "starttime": starttime},
                }
            ),
            encoding="utf-8",
        )
        result = self.run_tool(task=False, base=False)
        self.assert_refused(result, "worktree already holds a running lane")

    def test_tool_does_not_change_disposable_checkout(self):
        before = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=self.checkout,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.run_tool()
        after = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=self.checkout,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
