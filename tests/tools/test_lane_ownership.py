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


    def test_write_manifest_from_task_has_real_newlines(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp); (d/'logic').mkdir(); (d/'logic'/'bp').mkdir(parents=True,exist_ok=True); (d/'tools').mkdir()
            (d/'tools'/'x.py').write_text(''); (d/'logic'/'bp'/'x.lua').write_text('')
            task=d/'task.md'; task.write_text('## Files this lane owns\n- `!new.lua`\n- `tools/x.py` — scope\n- `logic/bp/`\n')
            out=d/'out.manifest'; r=subprocess.run([sys.executable,str(TOOL),'write-manifest','--task',str(task),'--out',str(out),'--repo',str(d)],capture_output=True,text=True)
            expected=b'# written by tools/lane_ownership.py write-manifest\n!new.lua\ntools/x.py\nlogic/bp/\n'
            self.assertEqual(r.returncode,0); self.assertEqual(r.stdout,f'wrote {out}: 3 path(s), 1 required\n'); self.assertEqual(out.read_bytes(),expected); self.assertNotIn(b'\\n',out.read_bytes()); self.assertEqual(len(out.read_bytes().splitlines()),4)

    def test_written_manifest_passes_dispatch_preflight(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp); (d/'tools').mkdir(); (d/'tools'/'x.py').write_text(''); task=d/'task.md'; task.write_text('## Files this lane owns\n- `tools/x.py`\n')
            out=d/'out'; r=subprocess.run([sys.executable,str(TOOL),'write-manifest','--task',str(task),'--out',str(out),'--repo',str(d)],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout)
            sys.path.insert(0,str(REPO/'tools'))
            import check_dispatch
            parsed=check_dispatch.parse_manifest(out,d)
            self.assertEqual(parsed.problems,()); self.assertEqual(check_dispatch._check_manifest_files(parsed,d),[])

    def test_write_manifest_refuses_task_without_owned_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp); task=d/'task.md'; task.write_text('## Files this lane owns\nlogic/a.lua, control.lua\n')
            out=d/'out'; r=subprocess.run([sys.executable,str(TOOL),'write-manifest','--task',str(task),'--out',str(out)],capture_output=True,text=True)
            self.assertEqual((r.returncode,r.stdout),(2,'refused: no owned paths in %s\n'%task)); self.assertFalse(out.exists())

    def test_write_manifest_refuses_missing_path_without_bang(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp); out=d/'out'; r=subprocess.run([sys.executable,str(TOOL),'write-manifest','--path','missing.lua','--out',str(out),'--repo',str(d)],capture_output=True,text=True)
            self.assertEqual((r.returncode,r.stdout),(2,'refused: owned path must exist at base or carry \'!\': missing.lua\n')); self.assertFalse(out.exists())

    def _task_repo(self,d, owned='module.lua'):
        base=self.build(d); task=d/'task.md'; task.write_text('## Files this lane owns\n- `%s`\n'%owned); git(d,'add','.'); git(d,'commit','-q','-m','task'); base=subprocess.run(['git','rev-parse','HEAD'],cwd=d,capture_output=True,text=True).stdout.strip(); return base,task

    def test_check_from_task_owned_file_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp); base,task=self._task_repo(d); (d/'module.lua').write_text('change'); git(d,'add','.'); git(d,'commit','-q','-m','lane')
            r=subprocess.run([sys.executable,str(TOOL),'check','--base',base,'--task',str(task),'--repo',str(d)],capture_output=True,text=True)
            self.assertEqual((r.returncode,r.stdout),(0,'owned-only: 1 file(s) changed, 0 required deliverable(s) present\n'))

    def test_check_from_task_foreign_file_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp); base,task=self._task_repo(d); (d/'control.lua').write_text('change'); git(d,'add','.'); git(d,'commit','-q','-m','lane')
            r=subprocess.run([sys.executable,str(TOOL),'check','--base',base,'--task',str(task),'--repo',str(d)],capture_output=True,text=True)
            self.assertEqual((r.returncode,r.stdout),(1,'OWNERSHIP: not owned by this lane: control.lua\n'))

    def test_check_reads_task_at_base_not_worktree(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp); base,task=self._task_repo(d); task.write_text('## Files this lane owns\n- `module.lua`\n- `control.lua`\n'); (d/'control.lua').write_text('change'); git(d,'add','.'); git(d,'commit','-q','-m','lane')
            r=subprocess.run([sys.executable,str(TOOL),'check','--base',base,'--task',str(task),'--repo',str(d)],capture_output=True,text=True)
            self.assertEqual((r.returncode,r.stdout),(1,'OWNERSHIP: not owned by this lane: control.lua\nOWNERSHIP: not owned by this lane: task.md\n'))

    def test_check_dot_is_literal(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp); base,task=self._task_repo(d,'pack.lua'); (d/'packXlua').write_text('change'); git(d,'add','.'); git(d,'commit','-q','-m','lane')
            r=subprocess.run([sys.executable,str(TOOL),'check','--base',base,'--task',str(task),'--repo',str(d)],capture_output=True,text=True)
            self.assertEqual((r.returncode,r.stdout),(1,'OWNERSHIP: not owned by this lane: packXlua\n'))

    def test_check_refuses_moving_ref_base(self):
        r=subprocess.run([sys.executable,str(TOOL),'check','--base','master','--manifest','ignored'],capture_output=True,text=True)
        self.assertEqual((r.returncode,r.stdout),(2,'refused: base must be a commit sha, not a ref: master\n'))

    def test_check_refuses_uncommitted_file(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp); base,task=self._task_repo(d); (d/'loose.lua').write_text('untracked')
            r=subprocess.run([sys.executable,str(TOOL),'check','--base',base,'--task',str(task),'--repo',str(d)],capture_output=True,text=True)
            self.assertEqual((r.returncode,r.stdout),(1,'OWNERSHIP: uncommitted change: loose.lua\n'))

    def test_check_runs_under_posix_sh_in_one_line(self):
        with tempfile.TemporaryDirectory() as temp:
            d=Path(temp); base,task=self._task_repo(d); (d/'module.lua').write_text('change'); git(d,'add','.'); git(d,'commit','-q','-m','lane')
            command='python3 %s check --base %s --task %s --repo %s'%(TOOL,base,task,d)
            r=subprocess.run(command,shell=True,executable='/bin/sh',capture_output=True,text=True)
            self.assertEqual((r.returncode,r.stdout),(0,'owned-only: 1 file(s) changed, 0 required deliverable(s) present\n'))

if __name__ == "__main__":
    unittest.main()
