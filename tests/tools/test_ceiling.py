"""Qualify tools/ceiling.sh on the rule that previously failed open: never time a refusal.

The user's limit is their own, stated 2026-09-21: no single calculation over 5 seconds, because it would be
unplayable. Round 13 carried the measured 29.41s in prose from one report to the next, and prose is not a
gate.

The failure mode this guards is specific and was measured: an earlier version of this check read
`{"ok":true,"validation":{"ok":false}}` and printed `ceiling-met 2ms`, because it had timed a refusal. A
refusal is fast, so a gate that counts one reports success exactly when the pipeline is most broken.

The accept path is qualified by hand rather than here, because it costs half a minute: on the pre-spine tree
at 498eff9, host legalcopilot-dev 2026-09-21, `player-am2-chain` delivered 314 entities in 27.20s and the
gate exited 1 naming the 5.00s limit; under a 600s limit the same run printed `ceiling-met` and exited 0.
"""

import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CEILING = ROOT / "tools" / "ceiling.sh"


def run(*args):
    done = subprocess.run(["sh", str(CEILING), *args], capture_output=True, text=True, cwd=ROOT)
    return done.returncode, done.stdout + done.stderr


class CeilingTest(unittest.TestCase):

    def test_CL1_a_missing_case_is_refused(self):
        status, output = run("no-such-case", "5.00")
        self.assertEqual(status, 2)
        self.assertIn("no such case input", output)

    def test_CL2_a_run_that_delivered_nothing_never_counts_as_fast(self):
        """A refusal is fast. Timing one reports success exactly when the pipeline is most broken."""
        status, output = run("assembler-chain-example", "5.00")
        self.assertEqual(status, 1)
        self.assertIn("nothing was delivered", output)
        self.assertNotIn("ceiling-met", output)

    def test_CL3_the_report_names_case_interpreter_elapsed_and_limit(self):
        _, output = run("assembler-chain-example", "5.00")
        for field in ("case=", "interpreter=", "elapsed=", "limit="):
            self.assertIn(field, output)


if __name__ == "__main__":
    unittest.main()
