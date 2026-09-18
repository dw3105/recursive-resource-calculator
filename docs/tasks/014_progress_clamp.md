# 014 — progress never goes backwards or negative

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-014`, branch `lane/014`, base = `feat/round-8-blueprints`, tag `wave-1-candidate` (resolve it with `git rev-parse wave-1-candidate`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This is a repair lane. A mutation batch planted a defect in `gui/progress_panel.lua` and every test stayed green, so the module's
tests do not cover that behaviour. Close the gap.

## What is true

**PRESERVE:**
- You own `gui/progress_panel.lua` and `tests/test_progress_panel.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_progress_panel.lua` stays. You add; you never weaken or delete.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- The planted defect: the clamp `math.max(0, math.floor(value))` became `math.floor(value)`, so a negative `done_units` reached the bar. Every one of the seven progress cases stayed green.
- The harness refuses a bar value outside [0, 1] with `LuaGuiElement::value must be a number in [0, 1]`, so an unclamped negative would raise rather than display.
- Assertions are `H.equal`, `H.near`, `H.deep_equal`, `H.errors`. They tag failures `[assert]`; anything else prints `[error]` and counts as no proof.
- Assert a value exists before reading it, so a failure is an assertion and not a nil index (`docs/feature-contracts.md` §2b).

## What to build

1. Add cases for the values a job can report when something upstream is wrong: a negative `done_units`, a negative `total_units`, `done_units` larger than `total_units`, a non-number, NaN, and infinity. In each, the bar keeps a value in [0, 1] and never raises.
2. Add a case proving the bar never moves backwards across two updates of one phase.
3. Name them in the existing `PP-<n>` sequence.
4. Plant the defect yourself to prove the new case fails with it and passes without it, and paste both runs.

## What done mean

```checks
{"name": "progress_clamp-tests", "command": "lua5.2 tests/test_progress_panel.lua && lua5.4 tests/test_progress_panel.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-1-candidate --manifest docs/tasks/014.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the new case failing against the planted defect, then passing once the defect is reverted.
- `git diff --stat wave-1-candidate HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit made afterwards moves the tree the proof
was taken against, and the supervisor refuses that proof with the reason `tree-moved`.

## Files this lane owns

- `gui/progress_panel.lua`
- `tests/test_progress_panel.lua`

Touch nothing else.

# bound: 3600s

Reviewer ask: can any reported progress make the bar raise or show a value outside [0, 1]?
