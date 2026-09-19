# 041 — release preparation that refuses, from a matrix it reads

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-041`, branch `lane/041`, base = `feat/round-8-blueprints`, tag `recovery-base` (resolve it with `git rev-parse recovery-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Stream C of the recovery plan. No Factorio is needed for any of this: every check is fail-closed and every test
uses a temporary archive it builds itself.

## What is true

**PRESERVE:**
- You own new `prepare_release.sh`, new `tools/release_gate.py`, new `tests/tools/test_release_gate.py`, `tools/evidence_receipt.py`, `generate_release.sh`, `tools/build_test_zip.sh`, new `docs/release-preparation.md`. Everything else is frozen; if you need a change elsewhere, stop and report.
- `tests/golden/required-matrix.json` is read-only for you. Stream E owns its content.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- `prepare_release.sh` does not exist. `generate_release.sh` packages a version and writes `logic/build_id.lua` into the packaged copy only, taking the commit from `RRC_CANDIDATE_SHA`. `tools/build_test_zip.sh` builds both branches from a tagged commit through `git archive`. `tools/evidence_receipt.py` files one observation against a stored archive.
- Evidence lives at `docs/engine-evidence/<candidate_sha>/<branch>/<case>.observation.json` and `.receipt.json`. The observation is written in game; the receipt is written here and carries `zip_sha256` computed here.
- `docs/feature-contracts.md` §17.4 fixes `tests/golden/required-matrix.json`: `case_id`, `branches`, `mods`, `outcome_kind`, `clauses`, `state` of `draft` or `accepted`, `prepared_input`. A `draft` case **fails** the gate; it is never a skipped success.
- The plan's rule, unchanged: build once, hash once, promote the same bytes. Rebuilding the candidate invalidates an earlier evidence binding.
- `tests/run.sh` discovers `tests/tools/test_*.py`, so your tooling tests run in every gate. Keep them cheap: no goldens, no archives larger than a few kilobytes.

## What to build

1. `prepare_release.sh <version> <2.0|2.1>` checks one branch, and `prepare_release.sh --release` declares readiness only when both branches and the whole required matrix pass, including the performance cases.
2. `tools/release_gate.py` does the work: read the matrix, select the required cases for that branch, and for each one check the stored archive's sha256, the packaged `build_id`, the observation digest, the receipt, the candidate SHA, the branch, the engine and mod environment, the outcome-specific assertions, and the canonical version and digest against the offline golden result.
3. Refuse, each with its own message: empty selection, absent case, draft baseline, unsupported schema version, missing branch, missing observation, missing receipt, unexpected rejection, rates below target, invalid timing, mismatched archive, mismatched environment. A feasible case that timed out is a failure, never a skip.
4. Never offer a way to force a release past missing evidence. A test zip stays possible and stays labelled a test build.
5. `tests/tools/test_release_gate.py`: one temporary archive per case, one rejection class per test, plus one valid synthetic path. A synthetic observation must be visibly a fixture and must never be filed under `docs/engine-evidence/`.
6. `docs/release-preparation.md`: the commands, in order, and what each refusal means.

## What done mean

```checks
{"name": "release-gate-tests", "command": "python3 -m unittest discover -s tests/tools -p 'test_release_gate.py' -t .", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 900}
{"name": "refuses-without-evidence", "command": "sh prepare_release.sh 1.1.99 2.0; test $? -ne 0 && echo refused-as-expected", "expect_exit": 0, "expect_regex": "refused-as-expected", "timeout_s": 600}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base recovery-base --manifest docs/tasks/041.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste one refusal per rejection class from your own tests.
- `git diff --stat recovery-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `prepare_release.sh`
- `tools/release_gate.py`
- `tests/tools/test_release_gate.py`
- `tools/evidence_receipt.py`
- `generate_release.sh`
- `tools/build_test_zip.sh`
- `docs/release-preparation.md`

Touch nothing else.

# bound: 2400s

Reviewer ask: does the gate refuse a draft case, a wrong archive hash and a missing branch, each with its own reason?
