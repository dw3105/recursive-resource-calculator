"""Cheap fail-closed tests for the release gate.

Every test owns its own tiny packaged archive.  The evidence is deliberately
filed below a temporary fixture directory, never below docs/engine-evidence.
"""

from __future__ import annotations

import importlib.util
import contextlib
import io
import json
import copy
import sys
import tempfile
import unittest
import unittest.mock
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


GATE = load_module(ROOT / "tools" / "release_gate.py", "rrc_test_release_gate")
RECEIPT = load_module(ROOT / "tools" / "evidence_receipt.py", "rrc_test_release_receipt")
PRODUCTION_EXAMPLE = json.loads(
    (ROOT / "docs" / "engine-evidence" / "examples" / "production.json").read_text(encoding="utf-8")
)


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


class ReleaseGateFixture:
    candidate = "fixture-candidate-sha"
    branch = "2.0"
    version = "1.1.99"
    case_id = "fixture-production"

    def __init__(self, root: Path):
        self.root = root
        self.matrix = root / "required-matrix.json"
        self.golden = root / "golden" / "cases"
        self.evidence = root / "fixture-evidence"
        self.archive = root / "fixture-test-build.zip"
        #The run this observation describes is identified by its input and configuration, not only by the
        #bytes inside the receipt. Without these a swapped input file was still accepted.
        self.prepared_input_name = f"{self.case_id}/prepared_input.json"
        self.prepared_input = None
        self.config = {"options": {"round_up": False}, "settings": {"beacon_sharing": True}}
        self.qualification_id = "fixture-harness-qualification"
        expected = {"blueprint": {"entities": [{"name": "stone-furnace", "position": {"x": 0, "y": 0}}]}}
        self.expected = expected
        self.manifest = {
            "schema_version": 1,
            "case_id": self.case_id,
            "factorio_branch": self.branch,
            "canonical_version": 1,
            "engine_scenario": {
                "initial_state": {},
                "supply": [],
                "drain": [],
                "warm_up_ticks": 5,
                "sampling_window_ticks": 10,
                "expected_rates": {"item/stone-brick": 1.0},
                "allowed_discrete_error": 0.01,
                "timeout_seconds": 10,
            },
            "expected_outcome": "production",
            "expected": "expected_canonical.json",
        }

    def make_matrix(self, **changes):
        case = {
            "case_id": self.case_id,
            "branches": [self.branch],
            "mods": ["base"],
            "outcome_kind": "production",
            "clauses": ["FIXTURE-01"],
            "state": "accepted",
            "prepared_input": self.prepared_input_name,
        }
        case.update(changes)
        write_json(self.matrix, {"schema_version": 1, "cases": [case]})

    def make_archive(self):
        build_id = (
            f'return {{candidate_sha = "{self.candidate}", mod_version = "{self.version}", '
            f'factorio_branch = "{self.branch}", packaged = true}}\n'
        )
        with zipfile.ZipFile(self.archive, "w", compression=zipfile.ZIP_STORED) as package:
            package.writestr(f"RRC-Fork_{self.version}/logic/build_id.lua", build_id)
            package.writestr("RRC-Fork_1.1.99/TEST_BUILD.txt", "fixture test build\n")

    def observation(self, **changes):
        production = copy.deepcopy(PRODUCTION_EXAMPLE["production"])
        production.update({
            "canonical_sha256": GATE.canonical_sha256(self.expected),
            "canonical_version": 1,
            "rates": {"item/stone-brick": 1.0},
            "warm_up": {"ticks": 5, "start_tick": 100, "end_tick": 104},
            "window": {"ticks": 10, "start_tick": 105, "end_tick": 114},
            "timings": {
                "generation_ticks": 18,
                "sampling_ticks": 10,
                "warm_up_ticks": 5,
                "wall_clock_seconds": 2.0,
            },
        })
        observation = {
            "schema_version": 1,
            "case_id": self.case_id,
            "outcome_kind": "production",
            "factorio_branch": self.branch,
            "factorio_version": f"{self.branch}.77",
            "candidate_sha": self.candidate,
            "runner_revision": "fixture-runner",
            "engine_version": f"{self.branch}.77",
            "active_mods": [{"name": "base", "version": f"{self.branch}.77"}],
            "mods": [{"name": "base", "version": f"{self.branch}.77"}],
            "force": "player",
            "surface": "nauvis",
            "environment": {
                "factorio_branch": self.branch,
                "mod_version": self.version,
                "active_mods": ["base"],
            },
            "production": production,
            "prepared_input_sha256": self.prepared_input_sha256(),
            "config_sha256": RECEIPT.config_sha256(self.config),
            "harness_qualification_id": self.qualification_id,
        }
        observation.update(changes)
        return observation

    def prepared_input_sha256(self):
        if self.prepared_input is not None and Path(self.prepared_input).is_file():
            return RECEIPT.file_sha256(Path(self.prepared_input))
        return "0" * 64

    def file_evidence(self, observation=None):
        observation = observation or self.observation()
        path = self.evidence / self.candidate / self.branch
        write_json(path / f"{self.case_id}.observation.json", observation)
        receipt = RECEIPT.make_receipt(
            observation, self.archive, expected_case=self.case_id, expected_candidate=self.candidate
        )
        write_json(path / f"{self.case_id}.receipt.json", receipt)

    def prepare(self, **case_changes):
        self.make_matrix(**case_changes)
        self.golden_case = self.golden / self.case_id
        write_json(self.golden_case / "manifest.json", self.manifest)
        write_json(self.golden_case / "expected_canonical.json", self.expected)
        #Written BEFORE the observation, so its declared hash is the hash of a file that really exists.
        self.prepared_input = self.golden_case / "prepared_input.json"
        write_json(self.prepared_input, {"case": self.case_id, "steps": []})
        self.make_archive()
        self.file_evidence()

    def run(self, branch=None, archive=None):
        return GATE.run_gate(
            branch or self.branch,
            matrix_path=self.matrix,
            candidate_sha=self.candidate,
            archive=archive or self.archive,
            evidence_root=self.evidence,
            golden_root=self.golden,
            expected_version=self.version,
        )


class ReleaseGateTests(unittest.TestCase):
    def fixture(self):
        temp = tempfile.TemporaryDirectory()
        fixture = ReleaseGateFixture(Path(temp.name))
        return temp, fixture

    def test_valid_synthetic_fixture_passes_without_touching_engine_evidence(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            self.assertEqual(fixture.run()[0]["status"], "accepted")
            self.assertFalse((ROOT / "docs" / "engine-evidence" / fixture.candidate).exists())

    def test_draft_baseline_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare(state="draft")
            with self.assertRaisesRegex(GATE.ReleaseGateError, "draft baseline"):
                fixture.run()

    def test_wrong_archive_hash_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            with fixture.archive.open("ab") as stream:
                stream.write(b"changed after receipt")
            with self.assertRaisesRegex(GATE.ReleaseGateError, "mismatched archive"):
                fixture.run()

    def test_missing_branch_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            with self.assertRaisesRegex(GATE.ReleaseGateError, "missing branch"):
                GATE.run_gate(
                    None,
                    matrix_path=fixture.matrix,
                    candidate_sha=fixture.candidate,
                    archive=fixture.archive,
                    evidence_root=fixture.evidence,
                    golden_root=fixture.golden,
                    expected_version=fixture.version,
                )

    def test_empty_selection_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare(branches=["2.1"])
            with self.assertRaisesRegex(GATE.ReleaseGateError, "empty selection"):
                fixture.run()

    def test_absent_case_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.make_matrix()
            with self.assertRaisesRegex(GATE.ReleaseGateError, "absent case"):
                fixture.run()

    def test_unsupported_schema_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            write_json(fixture.matrix, {"schema_version": 99, "cases": []})
            with self.assertRaisesRegex(GATE.ReleaseGateError, "unsupported schema version"):
                fixture.run()

    def test_missing_observation_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.make_matrix()
            fixture.golden_case = fixture.golden / fixture.case_id
            write_json(fixture.golden_case / "manifest.json", fixture.manifest)
            write_json(fixture.golden_case / "expected_canonical.json", fixture.expected)
            fixture.make_archive()
            with self.assertRaisesRegex(GATE.ReleaseGateError, "missing observation"):
                fixture.run()

    def test_missing_receipt_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            (fixture.evidence / fixture.candidate / fixture.branch / f"{fixture.case_id}.receipt.json").unlink()
            with self.assertRaisesRegex(GATE.ReleaseGateError, "missing receipt"):
                fixture.run()

    def test_unexpected_rejection_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation(
                outcome_kind="rejection",
                rejection={"stage": "preflight", "reason_codes": ["BP_REJ_FIXTURE"]},
            )
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "unexpected rejection"):
                fixture.run()

    def test_rates_below_target_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["production"]["rates"]["item/stone-brick"] = 0.1
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "rates below target"):
                fixture.run()

    def test_surplus_rate_is_accepted(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["production"]["rates"]["item/stone-brick"] = 1.5
            fixture.file_evidence(observation)
            self.assertEqual(fixture.run()[0]["status"], "accepted")

    def test_every_simultaneous_target_has_its_own_lower_bound(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.manifest["engine_scenario"]["expected_rates"] = {
                "item/stone-brick": 1.0,
                "item/iron-gear-wheel": 2.0,
            }
            fixture.prepare()
            observation = fixture.observation()
            observation["production"]["rates"] = {
                "item/stone-brick": 1.0,
                "item/iron-gear-wheel": 1.5,
            }
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(
                GATE.ReleaseGateError,
                r"rates below target: item/iron-gear-wheel measured 1\.5, target 2",
            ):
                fixture.run()

    def test_missing_or_empty_rate_data_is_refused(self):
        for empty_rates in (None, {}):
            temp, fixture = self.fixture()
            with temp:
                fixture.prepare()
                observation = fixture.observation()
                if empty_rates is None:
                    del observation["production"]["rates"]
                else:
                    observation["production"]["rates"] = empty_rates
                fixture.file_evidence(observation)
                with self.subTest(empty_rates=empty_rates):
                    with self.assertRaisesRegex(GATE.ReleaseGateError, "has no measured rates"):
                        fixture.run()

    def test_missing_or_invalid_window_is_refused(self):
        mutations = (
            lambda production: production.pop("window"),
            lambda production: production.update(window={"ticks": "not-a-number"}),
            lambda production: production.update(warm_up={"ticks": -1}),
        )
        for mutate in mutations:
            temp, fixture = self.fixture()
            with temp:
                fixture.prepare()
                observation = fixture.observation()
                mutate(observation["production"])
                fixture.file_evidence(observation)
                with self.subTest(mutate=mutate):
                    with self.assertRaisesRegex(GATE.ReleaseGateError, "invalid timing"):
                        fixture.run()

    def test_wall_clock_target_requires_wall_clock_measurement(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.manifest["engine_scenario"]["wall_clock_seconds"] = 3
            fixture.prepare()
            observation = fixture.observation()
            del observation["production"]["timings"]["wall_clock_seconds"]
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "wall_clock_seconds"):
                fixture.run()

    def test_flat_window_names_remain_accepted_as_synonyms(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            production = observation["production"]
            production["warm_up_ticks"] = production.pop("warm_up")["ticks"]
            production["sampling_window_ticks"] = production.pop("window")["ticks"]
            fixture.file_evidence(observation)
            self.assertEqual(fixture.run()[0]["status"], "accepted")

    def test_outcome_is_kept_as_a_legacy_synonym(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["outcome"] = observation.pop("production")
            fixture.file_evidence(observation)
            self.assertEqual(fixture.run()[0]["status"], "accepted")

    def test_canonical_digest_mismatch_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["production"]["canonical_sha256"] = "wrong-digest"
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "canonical mismatch"):
                fixture.run()

    def test_missing_21_evidence_blocks_readiness(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.branch = "2.1"
            fixture.version = "1.1.99"
            fixture.prepare(branches=["2.1"])
            evidence_path = fixture.evidence / fixture.candidate / fixture.branch
            (evidence_path / f"{fixture.case_id}.observation.json").unlink()
            with self.assertRaisesRegex(GATE.ReleaseGateError, "missing observation"):
                fixture.run()

    def test_examples_use_one_named_producer_outcome_block(self):
        for name in ("production", "rejection", "export"):
            example = json.loads(
                (ROOT / "docs" / "engine-evidence" / "examples" / f"{name}.json")
                .read_text(encoding="utf-8")
            )
            self.assertEqual(example["outcome_kind"], name)
            self.assertIn(name, example)
            self.assertIn("Synthetic example", example["note"])

    def test_invalid_timing_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["production"]["timed_out"] = True
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "invalid timing"):
                fixture.run()

    def test_mismatched_environment_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["engine_version"] = "2.1.19"
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "mismatched environment"):
                fixture.run()


if __name__ == "__main__":
    unittest.main()


class BindingTests(unittest.TestCase):
    """A receipt protects the bytes inside it. These prove it also says WHICH run those bytes describe.

    Measured before this existed: an observation with no input or configuration digest was `accepted`, and so
    was replacing a case's input file while reusing the unchanged observation and receipt.
    """

    def fixture(self):
        temp = tempfile.TemporaryDirectory()
        return temp, ReleaseGateFixture(Path(temp.name))

    def test_the_bound_fixture_is_accepted(self):
        #The positive control. Every refusal below is meaningless without it.
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            self.assertEqual(fixture.run()[0]["status"], "accepted")

    def test_an_observation_without_a_binding_is_refused(self):
        for missing in RECEIPT.REQUIRED_BINDINGS:
            with self.subTest(binding=missing):
                temp, fixture = self.fixture()
                with temp:
                    fixture.prepare()
                    observation = fixture.observation()
                    observation.pop(missing)
                    with self.assertRaises(RECEIPT.EvidenceError) as caught:
                        RECEIPT.make_receipt(observation, fixture.archive,
                                             expected_case=fixture.case_id,
                                             expected_candidate=fixture.candidate)
                    self.assertIn(missing, str(caught.exception))

    def test_a_declared_input_digest_is_recomputed_from_the_file(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["prepared_input_sha256"] = "f" * 64
            with self.assertRaises(RECEIPT.EvidenceError) as caught:
                RECEIPT.make_receipt(observation, fixture.archive,
                                     expected_case=fixture.case_id,
                                     expected_candidate=fixture.candidate,
                                     prepared_input=Path(fixture.prepared_input))
            self.assertIn("prepared input mismatch", str(caught.exception))

    def test_a_declared_config_digest_is_recomputed_from_the_file(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            config_path = Path(temp.name) / "config.json"
            write_json(config_path, fixture.config)
            observation = fixture.observation()
            observation["config_sha256"] = "e" * 64
            with self.assertRaises(RECEIPT.EvidenceError) as caught:
                RECEIPT.make_receipt(observation, fixture.archive,
                                     expected_case=fixture.case_id,
                                     expected_candidate=fixture.candidate,
                                     config=config_path)
            self.assertIn("configuration mismatch", str(caught.exception))

    def test_swapping_the_input_after_the_receipt_is_written_is_refused(self):
        #The exact probe that used to return `accepted`: the receipt and observation are untouched and still
        #agree with each other, but they no longer describe the input the case now names.
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            self.assertEqual(fixture.run()[0]["status"], "accepted")
            write_json(Path(fixture.prepared_input), {"case": fixture.case_id, "steps": ["swapped"]})
            with self.assertRaises(GATE.ReleaseGateError) as caught:
                fixture.run()
            self.assertIn("mismatched input", str(caught.exception))

    def test_a_case_naming_a_missing_input_is_refused(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            Path(fixture.prepared_input).unlink()
            with self.assertRaises(GATE.ReleaseGateError) as caught:
                fixture.run()
            self.assertIn("absent input", str(caught.exception))

    def test_a_receipt_binding_edited_apart_from_its_observation_is_refused(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            path = fixture.evidence / fixture.candidate / fixture.branch / f"{fixture.case_id}.receipt.json"
            receipt = json.loads(path.read_text())
            receipt["harness_qualification_id"] = "some-other-qualification"
            write_json(path, receipt)
            with self.assertRaises(GATE.ReleaseGateError) as caught:
                fixture.run()
            self.assertIn("harness_qualification_id", str(caught.exception))


class ReleaseArchiveArgumentTest(unittest.TestCase):
    """--release covers BOTH branches, so a single --archive can never be the exact package for either.

    That was already the intent, and release_gate.py:635 carried it out by replacing args.archive with None.
    The run then failed with "no archive supplied for branch 2.0" -- a complaint about a missing argument the
    caller had supplied, which sends the reader to look for a bug in their own command line.
    """

    def test_release_with_a_single_archive_is_refused(self):
        status = GATE.main(["--release", "--candidate", "deadbeef", "--archive", "/nonexistent/x.zip"])
        self.assertEqual(status, 2)

    def test_one_branch_still_accepts_its_own_archive(self):
        """The refusal must be about --release, never about --archive itself."""
        status = GATE.main(["2.0", "--candidate", "deadbeef", "--archive", "/nonexistent/x.zip"])
        self.assertEqual(status, 2)

    def test_the_refusal_names_archive_dir_as_the_way_through(self):
        buffer = io.StringIO()
        with contextlib.redirect_stderr(buffer):
            GATE.main(["--release", "--candidate", "deadbeef", "--archive", "/nonexistent/x.zip"])
        message = buffer.getvalue()
        self.assertIn("conflicting archive", message)
        self.assertIn("--archive-dir", message)


class HandoverReceiptTests(unittest.TestCase):
    def setUp(self):
        import hashlib, os, subprocess
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); self.archives=self.root/'archives'; self.archives.mkdir()
        self.head=subprocess.run(['git','-C',str(ROOT),'rev-parse','HEAD'],capture_output=True,text=True,check=True).stdout.strip()
        for fv in ('2.0','2.1'):
            p=self.archives/f'RRC-Fork_0.0.1_factorio-{fv}-test.zip'
            with zipfile.ZipFile(p,'w') as z:
                z.writestr('RRC-Fork_0.0.1/info.json','{"name":"RRC-Fork","version":"0.0.1"}')
                z.writestr('RRC-Fork_0.0.1/logic/build_id.lua',f'return {{candidate_sha = "{self.head}", mod_version = "0.0.1", factorio_branch = "{fv}", packaged = true}}')
        factorio=self.root/'factorio'; exe=factorio/'bin/x64/factorio'; exe.parent.mkdir(parents=True)
        exe.write_text('#!/bin/sh\necho "$@" >> "$FAKE_GAME_LOG"\nif [ "${FAKE_FACTORIO_FAIL:-}" = 1 ]; then echo "Error: mod crashed"; exit 1; fi\necho "Loading mod RRC-Fork 0.0.1 (data.lua)"\n'); exe.chmod(0o755)
        ft=self.root/'ft'; cli=ft/'node_modules/.bin/factorio-test'; cli.parent.mkdir(parents=True)
        cli.write_text('#!/usr/bin/env python3\nimport json,os,sys\na=sys.argv; open(os.environ["FAKE_GAME_LOG"],"a").write("gui\\n"); p=a[a.index("--output-file")+1]; json.dump({"tests":[{"path":"tests.game.test_gui > gui > toggle opens and closes twice","result":os.getenv("FAKE_GUI_RESULT","passed")}],"summary":{"describeBlockErrors":0}},open(p,"w"))\n'); cli.chmod(0o755)
        patch=ft/'node_modules/factorio-test-cli/factorio-process.js'; patch.parent.mkdir(parents=True); patch.write_text('}, 120_000);')
        ftz=self.root/'ftzips'; ftz.mkdir(); (ftz/'factorio-test_3.0.1.zip').write_bytes(b'a'); (ftz/'factorio-test_3.1.0.zip').write_bytes(b'b')
        lua=self.root/'lua'; lua.write_text('#!/usr/bin/env python3\nimport os,sys,time\ntime.sleep(float(os.getenv("FAKE_LUA_SLEEP","0"))); p=sys.argv[sys.argv.index("--output")+1]; open(p,"w").write("{\\\"ok\\\": "+os.getenv("FAKE_LUA_OK","true")+"}")\n'); lua.chmod(0o755)
        self.env={'FACTORIO_ROOT':str(factorio),'RRC_FT_DIR':str(ft),'FT_ZIP_DIR':str(ftz),'RRC_LUA':str(lua),'FAKE_GAME_LOG':str(self.root/'game.log')}
        for key in ('FACTORIO_ROOT','RRC_FT_DIR','FT_ZIP_DIR','RRC_LUA'): self.assertTrue(Path(self.env[key]).is_relative_to(self.root))
    def call(self,args,extra=None,keep_lane=False):
        import os
        out,err=io.StringIO(),io.StringIO(); env=dict(self.env); env.update(extra or {})
        with unittest.mock.patch.dict(os.environ,env,clear=False):
            if keep_lane: os.environ['LANE_RUN_ID']='x'
            else: os.environ.pop('LANE_RUN_ID',None)
            with contextlib.redirect_stdout(out),contextlib.redirect_stderr(err): rc=GATE.main(args)
        return rc,out.getvalue().splitlines(),err.getvalue().splitlines()
    def make_receipt(self, extra=None, flags=(), keep_lane=False):
        p=self.root/'receipt.json'; rc,out,err=self.call(['receipt','--archive-dir',str(self.archives),'--out',str(p),*flags],extra,keep_lane=keep_lane)
        return rc,p,out,err
    def test_receipt_all_ok_records_zip_sha_load_gui_calc(self):
        rc,p,out,_=self.make_receipt(); d=json.loads(p.read_text()); self.assertEqual(rc,0); self.assertEqual(set(d),{'schema','candidate_sha','written_utc','tested_in_game','not_tested_reason','zips','load','gui','calc_budget'}); self.assertEqual(d['tested_in_game'],'yes'); self.assertTrue(all(d[k][f]['result']=='ok' for k in ('load','gui') for f in ('2.0','2.1'))); self.assertEqual(d['calc_budget']['result'],'ok'); self.assertEqual(out,[f"receipt {p}: tested-in-game=yes load-2.0=ok load-2.1=ok gui-2.0=ok gui-2.1=ok calc=ok"])
        import hashlib
        for fv in ('2.0','2.1'): self.assertEqual(d['zips'][fv]['sha256'],hashlib.sha256(Path(d['zips'][fv]['path']).read_bytes()).hexdigest())
    def test_receipt_load_fail_recorded_and_handover_refuses(self):
        rc,p,_,_=self.make_receipt({'FAKE_FACTORIO_FAIL':'1'}); self.assertEqual(rc,1); d=json.loads(p.read_text()); self.assertEqual([d['load'][f]['result'] for f in ('2.0','2.1')],['FAIL','FAIL']); self.assertEqual(self.call(['handover','--receipt',str(p),'--archive-dir',str(self.archives)])[2],['handover refused: load-2.0 FAIL'])
    def test_receipt_gui_fail_recorded_and_handover_refuses(self):
        rc,p,_,_=self.make_receipt({'FAKE_GUI_RESULT':'failed'}); self.assertEqual(rc,1); d=json.loads(p.read_text()); self.assertEqual(d['gui']['2.0']['result'],'FAIL'); self.assertEqual(self.call(['handover','--receipt',str(p),'--archive-dir',str(self.archives)])[2],['handover refused: gui-2.0 FAIL'])
    def test_calc_over_budget_fails(self):
        rc,p,_,_=self.make_receipt({'FAKE_LUA_SLEEP':'3'},['--calc-budget','1']); self.assertEqual(rc,1); self.assertTrue(json.loads(p.read_text())['calc_budget']['cases']['player-red-science-1s']['detail'].startswith('FAIL timeout')); self.assertEqual(self.call(['handover','--receipt',str(p),'--archive-dir',str(self.archives)])[2],['handover refused: calc budget FAIL'])
    def test_calc_not_ok_output_fails(self):
        rc,p,_,_=self.make_receipt({'FAKE_LUA_OK':'false'}); self.assertEqual(rc,1); c=json.loads(p.read_text())['calc_budget']; self.assertTrue(c['cases']['player-red-science-1s']['detail'].startswith('FAIL not-ok')); self.assertEqual(c['result'],'FAIL')
    def test_no_game_records_not_tested_in_game(self):
        rc,p,out,_=self.make_receipt(flags=['--no-game']); d=json.loads(p.read_text()); self.assertEqual(rc,0); self.assertEqual(d['tested_in_game'],'no'); self.assertEqual(d['not_tested_reason'],'not tested in game: --no-game'); self.assertFalse(Path(self.env['FAKE_GAME_LOG']).exists()); self.assertEqual(self.call(['handover','--receipt',str(p),'--archive-dir',str(self.archives)])[2],['handover refused: not tested in game: --no-game; pass --accept-not-tested to hand over untested']); self.assertEqual(self.call(['handover','--receipt',str(p),'--archive-dir',str(self.archives),'--accept-not-tested'])[1],[f'handover ready: {self.head} NOT TESTED IN GAME'])
    def test_handover_refuses_missing_receipt(self):
        p=self.root/'missing.json'; self.assertEqual(self.call(['handover','--receipt',str(p),'--archive-dir',str(self.archives)])[2],[f'handover refused: no receipt: {p}'])
    def test_handover_refuses_zip_changed_after_receipt(self):
        _,p,_,_=self.make_receipt(); (self.archives/'RRC-Fork_0.0.1_factorio-2.0-test.zip').write_bytes(b'changed'); self.assertTrue(self.call(['handover','--receipt',str(p),'--archive-dir',str(self.archives)])[2][0].startswith('handover refused: zip 2.0 sha256 '))
    def test_lane_run_id_makes_game_not_run(self):
        rc,p,_,_=self.make_receipt(keep_lane=True); d=json.loads(p.read_text()); self.assertEqual(rc,1); self.assertEqual(d['load']['2.0']['result'],'not-run'); self.assertIn('lanes never run headless Factorio',d['load']['2.0']['reason']); self.assertEqual(d['tested_in_game'],'no'); self.assertFalse(Path(self.env['FAKE_GAME_LOG']).exists())
    def test_receipt_refuses_zip_branch_or_candidate_mismatch(self):
        p=self.archives/'RRC-Fork_0.0.1_factorio-2.1-test.zip'; tmp=p.with_suffix('.tmp')
        with zipfile.ZipFile(tmp,'w') as z:
            z.writestr('RRC-Fork_0.0.1/info.json','{"name":"RRC-Fork","version":"0.0.1"}'); z.writestr('RRC-Fork_0.0.1/logic/build_id.lua',f'return {{candidate_sha = "{self.head}", mod_version = "0.0.1", factorio_branch = "2.0", packaged = true}}')
        tmp.replace(p); out=self.root/'never.json'; rc,_,err=self.call(['receipt','--archive-dir',str(self.archives),'--out',str(out)]); self.assertEqual(rc,2); self.assertTrue(err[0].startswith('receipt refused: ')); self.assertFalse(out.exists())
    def test_calc_budget_refuses_in_lane_without_fake_lua(self):
        import os,subprocess
        env=dict(os.environ,LANE_RUN_ID='x'); env.pop('RRC_LUA',None); proc=subprocess.run(['sh',str(ROOT/'tools/calc_budget.sh'),'player-red-science-1s'],env=env,capture_output=True,text=True); self.assertEqual(proc.returncode,2); self.assertEqual(proc.stderr.strip(),'calc_budget: refuse, lanes never run a whole sheet')
    def test_calc_budget_prints_case_and_summary_lines(self):
        import os,subprocess,re
        env=dict(os.environ,**self.env); env.pop('LANE_RUN_ID',None); proc=subprocess.run(['sh',str(ROOT/'tools/calc_budget.sh'),'player-red-science-1s'],env=env,capture_output=True,text=True); self.assertEqual(proc.returncode,0); self.assertRegex(proc.stdout.splitlines()[0],r'^calc-budget player-red-science-1s ok wall_s=[0-9]+\.[0-9]{2} budget_s=5$'); self.assertEqual(proc.stdout.splitlines()[-1],'calc-budget-ok')
