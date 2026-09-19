# 031 — the calculation job carries the sheet's own revisions

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-031`, branch `lane/031`, base = `feat/round-8-blueprints`, tag `wave-3-repair-base` (resolve it with `git rev-parse wave-3-repair-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane. A mutation batch planted a defect in `logic/calc_pipeline.lua` and all seven pipeline cases stayed green, so that behaviour has no case.

## What is true

**PRESERVE:**
- You own `logic/calc_pipeline.lua` and `tests/test_calc_pipeline.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_calc_pipeline.lua` stays. You add; you never weaken or delete.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- The planted defect: `logic/calc_pipeline.lua:204` is `local revisions = snapshot.revisions or {sheet = 0, config = 0}`. Replacing it with the constant `{sheet = 0, config = 0}` keeps every case green.
- Why nothing fails: every fixture starts a sheet whose revisions are already zero. `logic/snapshot.lua:256-261` reads `player_storage.sheet_revision[sheet_id] or 0` and `player_storage.config_revision or 0`, and `logic/report_steps.lua:107-116` compares those same two numbers at publication. Zero equals zero, so a job that never reads the snapshot publishes exactly like one that does. `tests/test_calc_pipeline.lua:236-237` raises the sheet revision **after** the job starts, which the constant also refuses correctly.
- A player who has used Reset runs at `config_revision >= 1`: `logic/reset.lua` bumps it, per `docs/feature-contracts.md` and RESET-04. Under the constant, no calculation of that player would ever publish a report again.
- Publication refuses on a mismatch at `logic/report_steps.lua:395`, destroys the staged container, and leaves the old report in place.
- Bound every wait at 600 ticks and fail the case naming the stuck phase; a test that waits for a job that never finishes reads as a hang and burns the whole deadline.
- Assert a value exists before reading it, so a failure is an assertion and not a nil index (`docs/feature-contracts.md` §2b).

## What to build

1. Add a case that sets `storage[1].sheet_revision[sheet_id]` to a non-zero number **before** `CalcPipeline.start`, runs the job to completion, and asserts the report is published and equals the synchronous report.
2. Add a case that sets `storage[1].config_revision` to a non-zero number before the start, and asserts the same: a player who has reset still gets reports.
3. Add a case that the config revision alone, raised mid-run, drops the result and keeps the previous report, matching what `tests/test_calc_pipeline.lua:224` proves for the sheet revision.
4. Assert in one of them that the running job's stored revisions equal the sheet's revisions at start, so the job carries what it read.
5. Name them in the existing `CP-<n>` sequence.
6. Plant the defect yourself, paste each new case red, then paste them green with the defect reverted.

## What done mean

```checks
{"name": "pipeline-tests", "command": "lua5.2 tests/test_calc_pipeline.lua && lua5.4 tests/test_calc_pipeline.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-3-repair-base --manifest docs/tasks/031.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste each new case failing against the planted defect, then passing once the defect is reverted.
- `git diff --stat wave-3-repair-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `logic/calc_pipeline.lua`
- `tests/test_calc_pipeline.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does a sheet whose revisions start above zero still publish its report?
