# 024 — a port's lane count follows the belt it will use

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-024`, branch `lane/024`, base = `feat/round-8-blueprints`, tag `wave-2-candidate` (resolve it with `git rev-parse wave-2-candidate`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane. A mutation batch planted a defect in `logic/bp/plan.lua` and every test stayed green, so that behaviour has no case.

## What is true

**PRESERVE:**
- You own `logic/bp/plan.lua` and `tests/test_bp_plan.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_bp_plan.lua` stays. You add; you never weaken or delete.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- The planted defect: `lane_count` changed `math.ceil(rate / capacity - tolerance(rate))` to `math.floor(rate / capacity + 0.5)`, so a port needing 1.2 lanes asked for one. Every one of the twelve plan cases stayed green: no case reads `min_lanes` at all.
- `lane_count` reads `catalog.belt.lane_items_per_second`; a fluid port is always one lane.
- `min_lanes` is what the router later uses to decide how many parallel runs a port needs, so an undercount becomes a throughput shortfall in game rather than a visible error.
- Assert a value exists before reading it, so a failure is an assertion and not a nil index (`docs/feature-contracts.md` §2b).

## What to build

1. Add cases that pin `min_lanes` for an item port: a rate below one lane asks for one; a rate a hair above one lane asks for two; a rate exactly one lane asks for one, within the tolerance; a rate needing three lanes asks for three.
2. Add a case that a fluid port always asks for one lane whatever its rate.
3. Add a case that the lane count follows the selected belt: the same rate over a faster belt family asks for fewer lanes.
4. Name them in the existing `BP<n>` sequence.
5. Plant the defect yourself, paste the new case red, then paste it green with the defect reverted.

## What done mean

```checks
{"name": "plan_lanes-tests", "command": "lua5.2 tests/test_bp_plan.lua && lua5.4 tests/test_bp_plan.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-2-candidate --manifest docs/tasks/024.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the new case failing against the planted defect, then passing once the defect is reverted.
- `git diff --stat wave-2-candidate HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `logic/bp/plan.lua`
- `tests/test_bp_plan.lua`

Touch nothing else.

# bound: 2000s

Reviewer ask: does a port needing 1.2 lanes ask for two, and does a faster belt lower the count?
