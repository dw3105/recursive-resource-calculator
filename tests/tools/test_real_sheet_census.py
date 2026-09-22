"""The census tool and the gate that judges it.

The gate decides whether a lane's work is accepted, so its own arithmetic has to be tested directly. Round 14
shipped five lanes that all passed their gates and a product that did not work; a gate nobody tested is how
that happens. These cases drive `judge` with hand-built reports rather than by running the generator, so each
rule is exercised on its own and a failure names which rule broke.
"""

import importlib.util
import json
import os
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CASES = Path(REPO) / "tests" / "golden" / "cases"
REAL_SHEET_CENSUS = Path(REPO) / "tools" / "real_sheet_census.py"


def _load(name, relative):
    spec = importlib.util.spec_from_file_location(name, os.path.join(REPO, relative))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


census = _load("real_sheet_census", "tools/real_sheet_census.py")
gate = _load("census_gate", "tools/census_gate.py")


def _fake_interpreter(path):
    """Write a tiny generation-envelope producer for the CLI boundary test."""
    path.write_text(textwrap.dedent(
        """
        #!/usr/bin/env python3
        import json
        import sys

        arguments = sys.argv[1:]
        input_path = arguments[arguments.index("--input") + 1]
        output_path = arguments[arguments.index("--output") + 1]
        with open(input_path, encoding="utf-8") as stream:
            prepared = json.load(stream)

        if prepared.get("case_kind") == "broken":
            payload = {
                "ok": True,
                "stage": "done",
                "result": {
                    "entities": [{"name": "transport-belt"}],
                    "discarded_alternatives": [
                        {"candidate_id": "broken-1", "reason_codes": ["BP_V_TRANSPORT_UNUSED", "BP_V_TRANSFER_BROKEN"]},
                        {"candidate_id": "broken-2", "reason_codes": ["BP_V_TRANSPORT_UNUSED"]},
                    ],
                },
            }
        else:
            payload = {
                "ok": False,
                "stage": "failed",
                "errors": [{
                    "code": "BP_FAIL_SEARCH_BUDGET",
                    "reason_details": [
                        {"code": "BP_V_TRANSFER_BROKEN", "stage": "validate", "attempt": 1},
                        {"code": "BP_V_TRANSFER_BROKEN", "stage": "validate", "attempt": 2},
                        {"code": "BP_V_TRANSPORT_UNUSED", "stage": "validate", "attempt": 2},
                    ],
                }],
            }
        with open(output_path, "w", encoding="utf-8") as stream:
            json.dump(payload, stream)
        """
    ).lstrip(), encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def _run_census_cli(case_kind):
    """Run the real census command over a temporary input and a real envelope boundary."""
    with tempfile.TemporaryDirectory(prefix=".census-e2e-", dir=CASES) as directory:
        case = Path(directory)
        prepared = {
            "case_kind": case_kind,
            "provenance": {"certifiable": False},
        }
        (case / "prepared_input.json").write_text(json.dumps(prepared), encoding="utf-8")
        interpreter = case / "envelope-interpreter"
        _fake_interpreter(interpreter)
        return subprocess.run(
            ["python3", str(REAL_SHEET_CENSUS), "--case", case.name, "--ops", "17",
             "--interpreter", str(interpreter), "--timeout", "5", "--quiet"],
            cwd=REPO, text=True, capture_output=True, check=False,
        )


def report(rates, attempts=10, stage="failed", case="player-red-science-1s", ops=5000000,
           digest="abc", counts=None, delivered=0, ok=False):
    counts = counts or {code: int(rate * attempts) for code, rate in rates.items()}
    return {
        "schema_version": 1,
        "case": case,
        "prepared_input_sha256": digest,
        "ops_budget": ops,
        "interpreter": "lua5.2",
        "envelope": {"ok": ok, "stage": stage, "terminal_code": None if ok else "BP_FAIL_SEARCH_BUDGET"},
        "counters": {"validate_attempts": attempts, "entities_delivered": delivered},
        "census": counts,
        "rates": dict(rates),
    }


BASE = report({"BP_V_TRANSPORT_UNUSED": 100.0, "BP_V_TRANSFER_BROKEN": 20.0}, attempts=10)


class CensusExtraction(unittest.TestCase):
    def test_records_come_from_a_failure_envelope(self):
        payload = {"errors": [{"code": "BP_FAIL_SEARCH_BUDGET", "reason_details": [
            {"code": "BP_V_TRANSFER_BROKEN", "stage": "validate", "attempt": 1},
            {"code": "BP_V_TRANSFER_BROKEN", "stage": "validate", "attempt": 2},
        ]}]}
        counts, attempts = census.census_of(census.records_of(payload))
        self.assertEqual(counts["BP_V_TRANSFER_BROKEN"], 2)
        self.assertEqual(attempts["validate"], 2)

    def test_a_success_still_reports_its_discarded_alternatives(self):
        #A census that goes blind the moment the product starts working cannot show the last mile.
        payload = {"result": {"discarded_alternatives": [
            {"candidate_id": "c1", "reason_codes": ["BP_V_TRANSPORT_UNUSED"]},
        ]}}
        counts, attempts = census.census_of(census.records_of(payload))
        self.assertEqual(counts["BP_V_TRANSPORT_UNUSED"], 1)
        self.assertEqual(attempts["validate"], 1)


class CensusCommand(unittest.TestCase):
    def test_the_cli_counts_a_small_hand_countable_failure_envelope(self):
        completed = _run_census_cli("small")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["envelope"], {"ok": False, "stage": "failed",
                                               "terminal_code": "BP_FAIL_SEARCH_BUDGET"})
        self.assertEqual(report["counters"]["validate_attempts"], 2)
        self.assertEqual(report["census"], {"BP_V_TRANSFER_BROKEN": 2, "BP_V_TRANSPORT_UNUSED": 1})
        self.assertEqual(report["rates"], {"BP_V_TRANSFER_BROKEN": 1.0, "BP_V_TRANSPORT_UNUSED": 0.5})

    def test_the_cli_counts_discarded_reasons_from_a_broken_candidate(self):
        completed = _run_census_cli("broken")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["envelope"], {"ok": True, "stage": "done", "terminal_code": None})
        self.assertEqual(report["counters"]["validate_attempts"], 2)
        self.assertEqual(report["census"], {"BP_V_TRANSFER_BROKEN": 1, "BP_V_TRANSPORT_UNUSED": 2})
        self.assertEqual(report["rates"], {"BP_V_TRANSFER_BROKEN": 0.5, "BP_V_TRANSPORT_UNUSED": 1.0})


class PreparedInputCopies(unittest.TestCase):
    def test_generation_prepared_input_is_distinct_but_same_captured_payload(self):
        from tests.golden.lib.common import read_export

        export, _ = read_export(CASES / "player-red-science-1s" / "export.txt")
        top_level = export["prepared_input"]
        pinned = export["generation"]["prepared_input"]
        self.assertNotEqual(top_level, pinned)

        #The export writes empty lists as rrc_empty_list markers in the generation copy, while the top-level
        #copy has already been through the older empty-map encoding. Compare the three data-bearing portions;
        #metadata such as source_export is deliberately allowed to have its two export encodings.
        def normalise(value):
            if isinstance(value, dict):
                if value == {"rrc_empty_list": True}:
                    return {}
                return {key: normalise(item) for key, item in value.items()}
            if isinstance(value, list):
                return [normalise(item) for item in value]
            return value

        for field in ("catalog", "snapshot", "solver_result"):
            left = json.dumps(normalise(top_level[field]), sort_keys=True, separators=(",", ":")).encode()
            right = json.dumps(normalise(pinned[field]), sort_keys=True, separators=(",", ":")).encode()
            self.assertEqual(left, right, field)

        provenance = json.loads((CASES / "player-red-science-1s" / "provenance.json").read_text())
        self.assertEqual(provenance["prepared_input_source"], "generation.prepared_input")

    def test_attempts_count_candidates_and_not_records(self):
        payload = {"errors": [{"code": "X", "reason_details": [
            {"code": "BP_V_TRANSPORT_UNUSED", "stage": "validate", "attempt": 1} for _ in range(50)
        ]}]}
        counts, attempts = census.census_of(census.records_of(payload))
        self.assertEqual(counts["BP_V_TRANSPORT_UNUSED"], 50)
        self.assertEqual(attempts["validate"], 1)


class GateRules(unittest.TestCase):
    def judge(self, now, **kwargs):
        kwargs.setdefault("require_down", [])
        kwargs.setdefault("require_new", [])
        kwargs.setdefault("waivers", {})
        kwargs.setdefault("allow_total_rise", False)
        return gate.judge(now, BASE, kwargs["require_down"], kwargs["require_new"],
                          kwargs["waivers"], kwargs["allow_total_rise"])

    def test_the_baseline_against_itself_passes(self):
        self.assertEqual(self.judge(BASE), [])

    def test_a_fall_in_a_named_code_passes(self):
        now = report({"BP_V_TRANSPORT_UNUSED": 90.0, "BP_V_TRANSFER_BROKEN": 20.0}, attempts=10)
        self.assertEqual(self.judge(now, require_down=["BP_V_TRANSPORT_UNUSED"]), [])

    def test_a_named_code_that_does_not_fall_fails(self):
        failures = self.judge(BASE, require_down=["BP_V_TRANSPORT_UNUSED"])
        self.assertTrue(any("did not fall" in line for line in failures), failures)

    def test_any_rise_fails_without_a_waiver(self):
        now = report({"BP_V_TRANSPORT_UNUSED": 100.0, "BP_V_TRANSFER_BROKEN": 21.0}, attempts=10)
        failures = self.judge(now)
        self.assertTrue(any("increase, no waiver" in line for line in failures), failures)

    def test_a_brand_new_code_counts_as_a_rise(self):
        #Renaming a code would otherwise read as the old one falling to zero and nothing rising.
        now = report({"BP_V_TRANSPORT_UNUSED": 100.0, "BP_V_TRANSFER_BROKEN": 20.0,
                      "BP_V_INVENTED": 1.0}, attempts=10)
        failures = self.judge(now)
        self.assertTrue(any("BP_V_INVENTED" in line for line in failures), failures)

    def test_fewer_candidates_judged_is_not_an_improvement(self):
        #Halve the candidates and every raw count halves; the rate is what the gate reads, and the
        #denominator floor is what stops the rate being bought with a smaller denominator.
        now = report({"BP_V_TRANSPORT_UNUSED": 50.0, "BP_V_TRANSFER_BROKEN": 10.0}, attempts=4)
        failures = self.judge(now, require_down=["BP_V_TRANSPORT_UNUSED"])
        self.assertTrue(any("denominator floor" in line for line in failures), failures)

    def _delivery_baseline(self):
        # The frozen round baseline has 2,862 records spread over eleven rejected candidates.
        return report({"BP_A": 200.0, "BP_B": 60.0}, attempts=11,
                      counts={"BP_A": 2200, "BP_B": 662})

    def _delivered(self, counts):
        attempts = 1
        rates = {code: value / attempts for code, value in counts.items()}
        return report(rates, attempts=attempts, stage="done", counts=counts, delivered=1, ok=True)

    def test_delivery_with_fewer_discarded_alternatives_and_records_passes(self):
        baseline = self._delivery_baseline()
        now = self._delivered({"BP_A": 90, "BP_B": 31})
        self.assertEqual(gate.judge(now, baseline, [], [], {}, False), [])

    def test_no_delivery_with_fewer_judged_candidates_still_fails_denominator(self):
        baseline = self._delivery_baseline()
        now = report({"BP_A": 90.0, "BP_B": 31.0}, attempts=1,
                     counts={"BP_A": 90, "BP_B": 31})
        failures = gate.judge(now, baseline, [], [], {}, False)
        self.assertTrue(any("denominator floor: 1 candidates reached validate, the baseline reached 11" in line
                            for line in failures), failures)

    def test_delivery_with_an_absolute_record_rise_fails(self):
        baseline = self._delivery_baseline()
        now = self._delivered({"BP_A": 2400, "BP_B": 601})
        failures = gate.judge(now, baseline, [], [], {}, False)
        self.assertTrue(any("records 2200 -> 2400 (increase across delivery)" in line
                            for line in failures), failures)

    def test_delivery_named_require_down_code_must_fall_in_absolute_records(self):
        baseline = self._delivery_baseline()
        now = self._delivered({"BP_A": 2200, "BP_B": 31})
        failures = gate.judge(now, baseline, ["BP_A"], [], {}, False)
        self.assertTrue(any("BP_A records 2200 did not fall below the baseline 2200 across delivery" in line
                            for line in failures), failures)

    def test_stopping_before_the_search_is_not_an_improvement(self):
        now = report({}, attempts=10, stage="preflight")
        failures = self.judge(now)
        self.assertTrue(any("stage floor" in line for line in failures), failures)

    def test_a_different_sheet_is_refused_rather_than_compared(self):
        now = report({"BP_V_TRANSPORT_UNUSED": 1.0}, attempts=10, digest="different")
        failures = self.judge(now)
        self.assertTrue(any("not comparable" in line for line in failures), failures)
        self.assertTrue(all("did not fall" not in line for line in failures), failures)

    def test_a_small_baseline_is_refused_rather_than_gated_on(self):
        small = report({"BP_V_TINY": 0.4}, attempts=10, counts={"BP_V_TINY": 4})
        failures = gate.judge(small, small, ["BP_V_TINY"], [], {}, False)
        self.assertTrue(any("sensitivity" in line for line in failures), failures)

    def test_a_waiver_caps_a_rise_and_does_not_mute_it(self):
        now = report({"BP_V_TRANSPORT_UNUSED": 105.0, "BP_V_TRANSFER_BROKEN": 20.0}, attempts=10)
        waiver = {"BP_V_TRANSPORT_UNUSED": {"code": "BP_V_TRANSPORT_UNUSED", "ceiling_rate": 110.0}}
        self.assertEqual(self.judge(now, waivers=waiver), [])
        over = report({"BP_V_TRANSPORT_UNUSED": 120.0, "BP_V_TRANSFER_BROKEN": 20.0}, attempts=10)
        failures = self.judge(over, waivers=waiver)
        self.assertTrue(any("exceeds its waived ceiling" in line for line in failures), failures)

    def test_a_stricter_validator_is_judged_the_other_way_round(self):
        #A gate lane makes the validator see more, so "codes fell" is the wrong question to ask it.
        now = report({"BP_V_TRANSPORT_UNUSED": 100.0, "BP_V_TRANSFER_BROKEN": 20.0}, attempts=10)
        failures = self.judge(now, require_new=["BP_V_NEW_WITNESS"])
        self.assertTrue(any("BP_V_NEW_WITNESS" in line for line in failures), failures)


if __name__ == "__main__":
    unittest.main()
