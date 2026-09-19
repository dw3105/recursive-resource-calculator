"""The ownership gate: a compliant lane passes, a lane touching a frozen file fails, and two lanes never interfere.

The previous shape of this check compared against the spine rather than the lane's own base, used bash process
substitution under a verifier that runs /bin/sh, and wrote every lane's file list to one shared /tmp path.
"""

import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TOOL = REPO / "tools" / "lane_ownership.py"


def git(directory, *args):
    subprocess.run(["git", *args], cwd=directory, check=True, capture_output=True)


class LaneOwnership(unittest.TestCase):
    def build(self, directory, wave_file="wave1.lua"):
        """A repository with a wave base commit already carrying an earlier wave's file."""
        git(directory, "init", "-q")
        git(directory, "config", "user.email", "test@example.invalid")
        git(directory, "config", "user.name", "test")
        (directory / "control.lua").write_text("-- frozen, integrator only\n")
        git(directory, "add", ".")
        git(directory, "commit", "-q", "-m", "spine")
        (directory / wave_file).write_text("-- an earlier wave's module\n")
        git(directory, "add", ".")
        git(directory, "commit", "-q", "-m", "wave 1")
        base = subprocess.run(["git", "rev-parse", "HEAD"], cwd=directory, capture_output=True, text=True).stdout.strip()
        return base

    def manifest(self, directory, lines):
        path = directory / "lane.manifest"
        path.write_text("\n".join(lines) + "\n")
        return path

    def run_tool(self, directory, base, manifest):
        return subprocess.run([sys.executable, str(TOOL), "--base", base, "--manifest", str(manifest), "--repo", str(directory)],
                              capture_output=True, text=True)

    def test_a_lane_that_changed_only_its_own_files_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            base = self.build(directory)
            (directory / "snapshot.lua").write_text("return {}\n")
            (directory / "test_snapshot.lua").write_text("-- cases\n")
            git(directory, "add", ".")
            git(directory, "commit", "-q", "-m", "lane work")
            manifest = self.manifest(directory, ["snapshot.lua", "!test_snapshot.lua"])

            result = self.run_tool(directory, base, manifest)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("owned-only", result.stdout)

    def test_inheriting_an_earlier_wave_is_not_a_violation(self):
        """The lane forks the wave base, so the earlier wave's file is not in its diff at all."""
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            base = self.build(directory)
            (directory / "snapshot.lua").write_text("return {}\n")
            git(directory, "add", ".")
            git(directory, "commit", "-q", "-m", "lane work")
            manifest = self.manifest(directory, ["snapshot.lua"])

            result = self.run_tool(directory, base, manifest)
            self.assertEqual(result.returncode, 0, result.stdout)

    def test_a_directory_line_owns_the_tree_below_it(self):
        """A lane that creates a tree of case directories cannot list every file in its manifest in advance."""
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            base = self.build(directory)
            (directory / "golden").mkdir()
            (directory / "golden" / "cases").mkdir()
            (directory / "golden" / "run").write_text("#!/bin/sh\n")
            (directory / "golden" / "cases" / "one.json").write_text("{}\n")
            (directory / "golden" / "cases" / "two.json").write_text("{}\n")
            git(directory, "add", ".")
            git(directory, "commit", "-q", "-m", "lane work")
            manifest = self.manifest(directory, ["!golden/run", "!golden/cases/"])

            result = self.run_tool(directory, base, manifest)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("owned-only", result.stdout)

    def test_an_empty_required_directory_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            base = self.build(directory)
            (directory / "golden").mkdir()
            (directory / "golden" / "run").write_text("#!/bin/sh\n")
            git(directory, "add", ".")
            git(directory, "commit", "-q", "-m", "lane work")
            manifest = self.manifest(directory, ["!golden/run", "!golden/cases/"])

            result = self.run_tool(directory, base, manifest)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("required directory holds no changed file: golden/cases/", result.stdout)

    def test_a_file_outside_every_owned_directory_still_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            base = self.build(directory)
            (directory / "golden").mkdir()
            (directory / "golden" / "run").write_text("#!/bin/sh\n")
            (directory / "control.lua").write_text("-- a lane edited a frozen file\n")
            git(directory, "add", ".")
            git(directory, "commit", "-q", "-m", "lane work")
            manifest = self.manifest(directory, ["!golden/"])

            result = self.run_tool(directory, base, manifest)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("not owned by this lane: control.lua", result.stdout)

    def test_touching_a_frozen_file_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            base = self.build(directory)
            (directory / "snapshot.lua").write_text("return {}\n")
            (directory / "control.lua").write_text("-- a lane edited a frozen file\n")
            git(directory, "add", ".")
            git(directory, "commit", "-q", "-m", "lane work")
            manifest = self.manifest(directory, ["snapshot.lua"])

            result = self.run_tool(directory, base, manifest)
            self.assertEqual(result.returncode, 1)
            self.assertIn("not owned by this lane: control.lua", result.stdout)

    def test_a_missing_deliverable_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            base = self.build(directory)
            (directory / "snapshot.lua").write_text("return {}\n")
            git(directory, "add", ".")
            git(directory, "commit", "-q", "-m", "lane work without its test")
            manifest = self.manifest(directory, ["snapshot.lua", "!test_snapshot.lua"])

            result = self.run_tool(directory, base, manifest)
            self.assertEqual(result.returncode, 1)
            self.assertIn("required deliverable never changed: test_snapshot.lua", result.stdout)

    def test_two_lanes_checked_at_once_do_not_read_each_other(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            lanes = []
            for name, extra in (("compliant", None), ("violating", "control.lua")):
                directory = temp / name
                directory.mkdir()
                base = self.build(directory)
                (directory / "module.lua").write_text("return {}\n")
                if extra:
                    (directory / extra).write_text("-- forbidden edit\n")
                git(directory, "add", ".")
                git(directory, "commit", "-q", "-m", "lane work")
                lanes.append((directory, base, self.manifest(directory, ["module.lua"])))

            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(lambda lane: self.run_tool(*lane), lanes))

            self.assertEqual(results[0].returncode, 0, results[0].stdout)
            self.assertEqual(results[1].returncode, 1, results[1].stdout)

    def test_the_check_runs_under_posix_sh(self):
        """lane_verify runs checks through subprocess shell=True, which is /bin/sh here."""
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            base = self.build(directory)
            (directory / "snapshot.lua").write_text("return {}\n")
            git(directory, "add", ".")
            git(directory, "commit", "-q", "-m", "lane work")
            manifest = self.manifest(directory, ["snapshot.lua"])
            command = "python3 %s --base %s --manifest %s --repo %s" % (TOOL, base, manifest, directory)

            result = subprocess.run(command, shell=True, executable="/bin/sh", capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
