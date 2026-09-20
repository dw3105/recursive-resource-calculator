"""Fail-closed tests for the archive-to-player handoff command.

The fixture is a tiny git repository. Its builder and gates are harmless
doubles, but the handoff command still has to resolve a real candidate commit,
extract zips, stage that commit with git archive, discover cases, and write a
record. No agent, game, merge, or live checkout is involved.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "handoff.sh"


class HandoffFixture:
    def __init__(self, root: Path):
        self.root = root
        self._write_fixture()
        self._git("init", "-q")
        self._git("config", "user.name", "handoff-test")
        self._git("config", "user.email", "handoff-test@example.invalid")
        self._git("add", ".")
        self._git("commit", "-qm", "fixture")
        self.candidate = self._git("rev-parse", "HEAD").stdout.strip()

    def _git(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *args], cwd=self.root, text=True, capture_output=True, check=True
        )

    def _write(self, relative: str, content: str, executable: bool = False) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        if executable:
            path.chmod(0o755)

    def _write_fixture(self) -> None:
        self._write("info.json", '{"name": "RRC-Fork", "version": "0.0.0"}\n')
        self._write("logic/fixture.lua", "return true\n")
        self._write(
            "tests/harness.lua",
            """local H = {}
local passed, failed = 0, 0
function H.test(_, fn)
    local ok = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1 end
end
function H.done(name)
    print(string.format('%s: %d cases, %d passed, %d failed', name, passed + failed, passed, failed))
    os.exit(failed == 0 and 0 or 1)
end
return H
""",
        )
        self._write(
            "tests/test_quality_policy.lua",
            """local H = require 'tests.harness'
H.test('quality', function()
    if os.getenv('FAKE_QUALITY_RC') == '1' then error('planted quality failure') end
end)
H.done('quality')
""",
        )
        self._write("tests/test_fixture.lua", "local H = require 'tests.harness'\nH.test('fixture', function() end)\nH.done('fixture')\n")
        self._write(
            "tests/run.sh",
            """#!/bin/sh
if [ "$RRC_SHAPES" != '2.0,2.1' ] || [ "$LUAS" != 'lua5.2 lua5.4' ]; then
    echo 'narrowed environment' >&2
    exit 13
fi
printf '%s\n' 'test_fixture [Lua 5.2]: 1 cases, 1 passed, 0 failed'
printf '%s\n' 'test_fixture [Lua 5.4]: 1 cases, 1 passed, 0 failed'
printf '%s\n' 'test_quality_policy [Lua 5.2]: 1 cases, 1 passed, 0 failed'
printf '%s\n' 'test_quality_policy [Lua 5.4]: 1 cases, 1 passed, 0 failed'
printf '%s\n' 'test_export_completeness [Lua 5.2]: 1 cases, 1 passed, 0 failed'
printf '%s\n' 'test_export_completeness [Lua 5.4]: 1 cases, 1 passed, 0 failed'
exit "${FAKE_GATE_RC:-0}"
""",
            executable=True,
        )
        self._write(
            "tests/test_export_completeness.lua",
            """local function test()
    if os.getenv('FAKE_EXPORT_RC') == '1' then error('planted export failure') end
end
test()
print('export-completeness: 1 cases, 1 passed, 0 failed')
os.exit(tonumber(os.getenv('FAKE_EXPORT_RC') or '0'))
""",
        )
        self._write(
            "tests/acceptance/item_case.lua",
            "local H = require 'tests.harness'\nH.test('acceptance', function() end)\nH.done('acceptance')\n",
        )
        self._write(
            "tests/acceptance/run",
            """#!/bin/sh
printf '%s\n' 'acceptance: 1 cases, 1 passed, 0 failed'
exit "${FAKE_ACCEPTANCE_RC:-0}"
""",
            executable=True,
        )
        self._write(
            "tests/golden/run",
            """#!/bin/sh
if [ -n "${FAKE_GOLDEN_LOG:-}" ]; then
    printf '%s\\n' "$*" >> "$FAKE_GOLDEN_LOG"
fi
echo 'golden: 0 passed, 1 failed, 1 drafts, 0 captured'
exit "${FAKE_GOLDEN_RC:-9}"
""",
            executable=True,
        )
        self._write("docs/seed.md", "fixture docs\n")
        self._write("tests/tools/__init__.py", "")
        self._write("tests/tools/test_fixture.py", "import unittest\n\nclass FixtureTest(unittest.TestCase):\n    def test_fixture(self):\n        pass\n")
        self._write("tools/handoff.sh", SCRIPT.read_text(encoding="utf-8"), executable=True)
        self._write("prepare_release.sh", (ROOT / "prepare_release.sh").read_text(encoding="utf-8"), executable=True)
        self._write(
            "tools/release_gate.py",
            """#!/usr/bin/env python3
import os
from pathlib import Path
import sys

log = os.environ.get('FAKE_RELEASE_GATE_LOG')
if log:
    with Path(log).open('a', encoding='utf-8') as stream:
        stream.write(' '.join(sys.argv[1:]) + '\\n')
raise SystemExit(int(os.environ.get('FAKE_RELEASE_GATE_RC', '0')))
""",
            executable=True,
        )
        self._write(
            "tools/build_test_zip.sh",
            """#!/bin/sh
set -eu
if [ -n "${FAKE_BUILD_MARKER:-}" ]; then
    : > "$FAKE_BUILD_MARKER"
fi
sha=$1
v20=$2
v21=$3
out=$4
mkdir -p "$out"
make_zip() {
    version=$1
    branch=$2
    work=$(mktemp -d "${TMPDIR:-/tmp}/handoff-fixture.XXXXXX")
    mkdir "$work/RRC-Fork_${version}"
    git archive "$sha" | tar -x -C "$work/RRC-Fork_${version}"
    printf '%s\n' "${FAKE_BUILD_TAG:-default}" > "$work/RRC-Fork_${version}/build-marker"
    python3 -m zipfile -c "$out/RRC-Fork_${version}_factorio-${branch}-test.zip" "$work/RRC-Fork_${version}"
}
make_zip "$v20" 2.0
make_zip "$v21" 2.1
""",
            executable=True,
        )

    #Variables the real command reads are cleared before every fixture run, and restored only when a case asks
    #for them. An ambient RRC_HANDOFF_KEEP_ARCHIVES once made this suite copy its own 1.0.0 doubles into the
    #operator's handover directory, beside the archives a player was about to receive.
    AMBIENT = ("RRC_HANDOFF_KEEP_ARCHIVES", "RRC_SHAPES", "LUAS", "FAKE_GATE_RC", "FAKE_ACCEPTANCE_RC",
               "FAKE_GOLDEN_RC", "FAKE_EXPORT_RC", "FAKE_BUILD_TAG", "FAKE_GOLDEN_LOG",
               "FAKE_RELEASE_GATE_RC", "FAKE_RELEASE_GATE_LOG", "FAKE_BUILD_MARKER")

    def run(self, diagnostic: bool = False, **environment: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        for name in self.AMBIENT:
            env.pop(name, None)
        env.update(environment)
        command = ["sh", str(self.root / "tools" / "handoff.sh")]
        if diagnostic:
            command.append("--diagnostic")
        command.extend([self.candidate, "1.0.0", "1.0.0"])
        return subprocess.run(
            command,
            cwd=self.root,
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )

    def promote(self, archive: Path, **environment: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        for name in self.AMBIENT:
            env.pop(name, None)
        env.update(environment)
        return subprocess.run(
            ["sh", str(self.root / "prepare_release.sh"), "1.0.0", "2.0",
             "--archive", str(archive), "--candidate", self.candidate],
            cwd=self.root,
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )

    def records(self) -> list[Path]:
        return sorted((self.root / "docs" / "handoff" / self.candidate).glob("*.json"))


class HandoffTests(unittest.TestCase):
    def test_an_ambient_keep_directory_never_receives_fixture_archives(self):
        #The suite runs inside the extracted package during a real handoff, so an exported keep directory is
        #present in the environment. Nothing from this fixture may land in it.
        raw, fixture = self.fixture()
        with raw:
            operator = fixture.root / "operator-handover"
            operator.mkdir()
            os.environ["RRC_HANDOFF_KEEP_ARCHIVES"] = str(operator)
            try:
                result = fixture.run(FAKE_GOLDEN_RC="0")
            finally:
                os.environ.pop("RRC_HANDOFF_KEEP_ARCHIVES", None)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(sorted(operator.iterdir()), [], "a fixture run wrote into the operator's directory")

    def setUp(self) -> None:
        # Keep the red-proof useful: deleting the new command produces normal
        # assertion failures, rather than an import/setup error.
        self.assertTrue(SCRIPT.is_file(), f"missing owned command: {SCRIPT}")

    def fixture(self):
        raw = tempfile.TemporaryDirectory()
        return raw, HandoffFixture(Path(raw.name))

    def test_a_planted_gating_failure_refuses(self):
        raw, fixture = self.fixture()
        with raw:
            result = fixture.run(FAKE_GATE_RC="7", FAKE_GOLDEN_RC="0")
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            records = fixture.records()
            self.assertEqual(len(records), 1)
            record = json.loads(records[0].read_text(encoding="utf-8"))
            self.assertEqual(record["result"], "refused")
            test_checks = [check for check in record["checks"] if check["name"] == "tests-run"]
            self.assertEqual(len(test_checks), 2)
            self.assertTrue(any(check["exit"] == 7 for check in test_checks))

    def test_a_narrowed_environment_cannot_pass_as_a_full_run(self):
        raw, fixture = self.fixture()
        with raw:
            result = fixture.run(RRC_SHAPES="2.0", LUAS="lua5.2", FAKE_GOLDEN_RC="23")
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            record = json.loads(fixture.records()[0].read_text(encoding="utf-8"))
            self.assertEqual(record["result"], "refused")
            self.assertTrue(any("RRC_SHAPES" in reason for reason in record["reasons"]))

    def test_two_archive_sets_keep_two_records(self):
        raw, fixture = self.fixture()
        with raw:
            first = fixture.run(FAKE_BUILD_TAG="first", FAKE_GOLDEN_RC="0")
            second = fixture.run(FAKE_BUILD_TAG="second", FAKE_GOLDEN_RC="0")
            self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
            self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
            records = fixture.records()
            self.assertEqual(len(records), 2)
            digests = {json.loads(path.read_text(encoding="utf-8"))["archive_set_sha256"] for path in records}
            self.assertEqual(len(digests), 2)

    def test_a_refused_attempt_is_retained(self):
        raw, fixture = self.fixture()
        with raw:
            result = fixture.run(FAKE_ACCEPTANCE_RC="4", FAKE_GOLDEN_RC="0")
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            records = fixture.records()
            self.assertEqual(len(records), 1)
            record = json.loads(records[0].read_text(encoding="utf-8"))
            self.assertEqual(record["result"], "refused")
            self.assertTrue(record["reasons"])

    def test_a_passing_run_can_keep_exactly_the_archives_it_verified(self):
        raw, fixture = self.fixture()
        with raw:
            kept = fixture.root / "kept"
            result = fixture.run(FAKE_GATE_RC="0", FAKE_GOLDEN_RC="0",
                                 RRC_HANDOFF_KEEP_ARCHIVES=str(kept))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            record = json.loads(fixture.records()[0].read_text(encoding="utf-8"))
            self.assertEqual(record["result"], "pass")
            names = sorted(path.name for path in kept.iterdir())
            self.assertEqual(len(names), 2, names)
            kept_digests = {
                hashlib.sha256((kept / name).read_bytes()).hexdigest() for name in names
            }
            self.assertEqual(
                kept_digests,
                {entry["sha256"] for entry in record["archives"]},
                "the kept bytes are the verified bytes",
            )

    def test_a_refused_run_hands_over_no_archive(self):
        raw, fixture = self.fixture()
        with raw:
            kept = fixture.root / "kept"
            result = fixture.run(FAKE_GATE_RC="7", FAKE_GOLDEN_RC="0",
                                 RRC_HANDOFF_KEEP_ARCHIVES=str(kept))
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertFalse(kept.exists() and any(kept.iterdir()), "a refusal hands over nothing")

    def test_a_red_corpus_refuses_a_non_diagnostic_handoff(self):
        raw, fixture = self.fixture()
        with raw:
            result = fixture.run(FAKE_GOLDEN_RC="19")
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            record = json.loads(fixture.records()[0].read_text(encoding="utf-8"))
            corpus = [check for check in record["checks"] if check["name"] == "golden-corpus"]
            self.assertEqual(len(corpus), 2)
            self.assertTrue(all(check["exit"] == 19 for check in corpus))
            self.assertEqual({check["branch"] for check in corpus}, {"2.0", "2.1"})
            self.assertEqual(record["result"], "refused")
            self.assertFalse(record["informational"])

    def test_a_handoff_runs_the_corpus_for_its_own_branch(self):
        raw, fixture = self.fixture()
        with raw:
            log = fixture.root / "golden-args.log"
            result = fixture.run(FAKE_GOLDEN_RC="0", FAKE_GOLDEN_LOG=str(log))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(log.read_text(encoding="utf-8").splitlines(),
                             ["--branch 2.0 --drafts report", "--branch 2.1 --drafts report"])
            record = json.loads(fixture.records()[0].read_text(encoding="utf-8"))
            corpus = [check for check in record["checks"] if check["name"] == "golden-corpus"]
            self.assertEqual({(check["name"], check["branch"]) for check in corpus},
                             {("golden-corpus", "2.0"), ("golden-corpus", "2.1")})
            self.assertTrue(all(check["log_sha256"] for check in corpus))

    def test_promotion_accepts_an_existing_archive_and_never_rebuilds(self):
        raw, fixture = self.fixture()
        with raw:
            archive = fixture.root / "existing.zip"
            archive.write_bytes(b"archive that already exists")
            build_marker = fixture.root / "build-called"
            golden_log = fixture.root / "promotion-golden.log"
            gate_log = fixture.root / "promotion-gate.log"
            result = fixture.promote(
                archive,
                FAKE_GOLDEN_RC="0",
                FAKE_GOLDEN_LOG=str(golden_log),
                FAKE_RELEASE_GATE_LOG=str(gate_log),
                FAKE_BUILD_MARKER=str(build_marker),
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(build_marker.exists(), "promotion rebuilt an existing archive")
            self.assertEqual(golden_log.read_text(encoding="utf-8").splitlines(),
                             ["--branch 2.0"])
            self.assertIn("--archive " + str(archive), gate_log.read_text(encoding="utf-8"))
            self.assertIn("release verdict: verified", result.stdout)

            refused = fixture.promote(
                archive,
                FAKE_GOLDEN_RC="0",
                FAKE_RELEASE_GATE_RC="7",
            )
            self.assertEqual(refused.returncode, 7, refused.stdout + refused.stderr)
            self.assertNotIn("verified", refused.stdout + refused.stderr)

    def test_a_diagnostic_run_survives_a_red_corpus_and_stays_unverified_internal(self):
        raw, fixture = self.fixture()
        with raw:
            kept = fixture.root / "kept"
            result = fixture.run(diagnostic=True, FAKE_GOLDEN_RC="19",
                                 RRC_HANDOFF_KEEP_ARCHIVES=str(kept))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            record = json.loads(fixture.records()[0].read_text(encoding="utf-8"))
            self.assertEqual(record["mode"], "diagnostic")
            self.assertEqual(
                [archive["verdict"] for archive in record["archives"]],
                ["unverified_internal", "unverified_internal"],
            )
            self.assertEqual(record["result"], "pass")

    def test_a_diagnostic_run_can_never_write_verified(self):
        raw, fixture = self.fixture()
        with raw:
            result = fixture.run(diagnostic=True, FAKE_BUILD_TAG="verified", FAKE_GOLDEN_RC="0")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            record = json.loads(fixture.records()[0].read_text(encoding="utf-8"))
            self.assertNotIn('"verified"', json.dumps(record, sort_keys=True))
            self.assertTrue(all(archive["verdict"] != "verified" for archive in record["archives"]))

    def test_a_diagnostic_run_records_every_release_blocker(self):
        raw, fixture = self.fixture()
        with raw:
            result = fixture.run(
                diagnostic=True,
                FAKE_GATE_RC="7",
                FAKE_ACCEPTANCE_RC="4",
                FAKE_QUALITY_RC="1",
                FAKE_GOLDEN_RC="19",
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            record = json.loads(fixture.records()[0].read_text(encoding="utf-8"))
            blockers = {(blocker["branch"], blocker["name"]): blocker["exit"]
                        for blocker in record["blockers"]}
            for branch in ("2.0", "2.1"):
                self.assertEqual(blockers[(branch, "tests-run")], 7)
                self.assertEqual(blockers[(branch, "acceptance")], 4)
                self.assertEqual(blockers[(branch, "quality-policy")], 1)
                self.assertEqual(blockers[(branch, "golden-corpus")], 19)

    def test_an_incomplete_corpus_does_not_block_a_diagnostic_build(self):
        raw, fixture = self.fixture()
        with raw:
            kept = fixture.root / "kept"
            result = fixture.run(diagnostic=True, FAKE_GOLDEN_RC="19",
                                 RRC_HANDOFF_KEEP_ARCHIVES=str(kept))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(len(list(kept.iterdir())), 2)
            record = json.loads(fixture.records()[0].read_text(encoding="utf-8"))
            corpus = [blocker for blocker in record["blockers"]
                      if blocker["name"] == "golden-corpus"]
            self.assertEqual(len(corpus), 2)
            self.assertTrue(all(blocker["exit"] == 19 for blocker in corpus))

    def test_a_failing_export_check_refuses_the_diagnostic_build(self):
        raw, fixture = self.fixture()
        with raw:
            kept = fixture.root / "kept"
            result = fixture.run(diagnostic=True, FAKE_EXPORT_RC="23",
                                 RRC_HANDOFF_KEEP_ARCHIVES=str(kept))
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(kept.exists() and any(kept.iterdir()), "a refused diagnostic hands over nothing")
            records = fixture.records()
            self.assertEqual(len(records), 1, result.stdout + result.stderr)
            record = json.loads(records[0].read_text(encoding="utf-8"))
            self.assertEqual(record["result"], "refused")
            export_checks = [check for check in record["checks"]
                             if check["name"] == "export-completeness"]
            self.assertEqual(len(export_checks), 2)
            self.assertTrue(all(check["exit"] == 23 for check in export_checks))

    def test_a_diagnostic_receipt_carries_the_exact_candidate_and_archive_identity(self):
        raw, fixture = self.fixture()
        with raw:
            kept = fixture.root / "kept"
            result = fixture.run(diagnostic=True, FAKE_GOLDEN_RC="19",
                                 RRC_HANDOFF_KEEP_ARCHIVES=str(kept))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            record = json.loads(fixture.records()[0].read_text(encoding="utf-8"))
            self.assertEqual(record["candidate_sha"], fixture.candidate)
            kept_digests = {
                hashlib.sha256(path.read_bytes()).hexdigest()
                for path in kept.iterdir()
            }
            self.assertEqual(kept_digests,
                             {archive["sha256"] for archive in record["archives"]})

    def test_the_ordinary_path_is_unchanged_by_the_diagnostic_mode(self):
        raw, fixture = self.fixture()
        with raw:
            kept = fixture.root / "kept"
            result = fixture.run(FAKE_GOLDEN_RC="0", RRC_HANDOFF_KEEP_ARCHIVES=str(kept))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            record = json.loads(fixture.records()[0].read_text(encoding="utf-8"))
            self.assertNotIn("mode", record)
            self.assertEqual(record["result"], "pass")
            self.assertTrue(all("verdict" not in archive for archive in record["archives"]))
            self.assertEqual(len(record["informational"]), 0)
            self.assertEqual(len([check for check in record["checks"]
                                 if check["name"] == "golden-corpus"]), 2)


if __name__ == "__main__":
    unittest.main()
