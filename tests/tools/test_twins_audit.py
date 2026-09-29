"""Round 48 D4: python auditors on every twin's published blueprint (tools/twin_bp.lua).

Each twin's `audit` table names the auditor counts it pins, e.g. {lane_sim = {bleed = 1}, blueprint_audit =
{cycles = 0}}; only listed keys are asserted. Every twin's string must decode with no schema problem.
"""
import json, os, re, subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import blueprint_audit  # noqa: E402

LUA = os.environ.get("LUA", "lua5.2")


def twins():
    out = subprocess.run(["find", "tests/twins", "-name", "*.lua", "-not", "-path", "*/lib/*", "-not", "-name", "required.lua"],
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
    return sorted(out)


def audit_of(path):
    """The twin's `audit` table as {tool: {key: int}}, read by the twin's own Lua loader."""
    out = subprocess.run([LUA, "tools/twin_bp.lua", "--audit", path], cwd=ROOT, capture_output=True, text=True,
                         check=True).stdout
    result = {}
    for line in out.splitlines():
        tool, key, value = line.split()
        result.setdefault(tool, {})[key] = int(value)
    return result


class TwinAudit(unittest.TestCase):
    def test_twins_exist(self):
        self.assertTrue(twins())

    def test_every_twin(self):
        for path in twins():
            with self.subTest(twin=path):
                bp = subprocess.run([LUA, "tools/twin_bp.lua", path], cwd=ROOT, capture_output=True, text=True, timeout=60)
                self.assertEqual(bp.returncode, 0, bp.stderr)
                text = bp.stdout.strip()
                if text.startswith("NO-BP "):
                    self.assertEqual(audit_of(path), {}, "a twin with no layout pins no auditor count")
                    continue
                self.assertEqual(blueprint_audit.string_problems(text), [], "string decodes cleanly")
                want = audit_of(path)
                with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
                    f.write(text + "\n")
                    bp_file = f.name
                try:
                    if "blueprint_audit" in want:
                        out = subprocess.run([sys.executable, "tools/blueprint_audit.py", "--json", "-q", bp_file], cwd=ROOT,
                                             capture_output=True, text=True, timeout=60)
                        counts = json.loads(out.stdout)
                        for key, value in want["blueprint_audit"].items():
                            self.assertEqual(counts.get(key), value, f"blueprint_audit {key}")
                    if "lane_sim" in want:
                        cat = subprocess.run([LUA, "tools/twin_bp.lua", "--catalog", path], cwd=ROOT, capture_output=True,
                                             text=True, timeout=60, check=True).stdout
                        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as c:
                            c.write(cat)
                            cat_file = c.name
                        try:
                            out = subprocess.run([sys.executable, "tools/lane_sim.py", bp_file, "--input", cat_file], cwd=ROOT,
                                                 capture_output=True, text=True, timeout=60)
                        finally:
                            os.unlink(cat_file)
                        m = re.search(r"LANE-SIM mixed=(\d+) starved=(\d+) bleed=(\d+)", out.stdout)
                        self.assertIsNotNone(m, out.stdout + out.stderr)
                        got = dict(zip(("mixed", "starved", "bleed"), map(int, m.groups())))
                        for key, value in want["lane_sim"].items():
                            self.assertEqual(got[key], value, f"lane_sim {key}")
                    unknown = set(want) - {"blueprint_audit", "lane_sim"}
                    self.assertEqual(unknown, set(), "audit tools known")
                finally:
                    os.unlink(bp_file)


if __name__ == "__main__":
    unittest.main()
