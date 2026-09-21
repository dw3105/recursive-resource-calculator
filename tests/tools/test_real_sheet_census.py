"""The census tool and the gate that judges it.

The gate decides whether a lane's work is accepted, so its own arithmetic has to be tested directly. Round 14
shipped five lanes that all passed their gates and a product that did not work; a gate nobody tested is how
that happens. These cases drive `judge` with hand-built reports rather than by running the generator, so each
rule is exercised on its own and a failure names which rule broke.
"""

import importlib.util
import os
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _load(name, relative):
    spec = importlib.util.spec_from_file_location(name, os.path.join(REPO, relative))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


census = _load("real_sheet_census", "tools/real_sheet_census.py")
gate = _load("census_gate", "tools/census_gate.py")


def report(rates, attempts=10, stage="failed", case="player-red-science-1s", ops=5000000,
           digest="abc", counts=None):
    counts = counts or {code: int(rate * attempts) for code, rate in rates.items()}
    return {
        "schema_version": 1,
        "case": case,
        "prepared_input_sha256": digest,
        "ops_budget": ops,
        "interpreter": "lua5.2",
        "envelope": {"ok": False, "stage": stage, "terminal_code": "BP_FAIL_SEARCH_BUDGET"},
        "counters": {"validate_attempts": attempts},
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
