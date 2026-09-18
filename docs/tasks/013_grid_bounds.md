# 013 — a placement that overhangs the grid is refused

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-013`, branch `lane/013`, base = `feat/round-8-blueprints`, tag `wave-1-candidate` (resolve it with `git rev-parse wave-1-candidate`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This is a repair lane. A mutation batch planted a defect in `logic/bp/grid.lua` and every test stayed green, so the module's
tests do not cover that behaviour. Close the gap.

## What is true

**PRESERVE:**
- You own `logic/bp/grid.lua` and `tests/test_grid.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_grid.lua` stays. You add; you never weaken or delete.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- The planted defect: `Grid.can_place` changed its right-edge test from `rect.x + rect.w > grid.w` to `rect.x + rect.w > grid.w + 1`, so a rect hanging one tile past the right edge was accepted. Every one of the twelve grid cases stayed green.
- Case `G9 can_place refuses overlap but accepts an allowed owner` covers overlap, not containment.
- Assertions are `H.equal`, `H.near`, `H.deep_equal`, `H.errors`. They tag failures `[assert]`; anything else prints `[error]` and counts as no proof.
- Assert a value exists before reading it, so a failure is an assertion and not a nil index (`docs/feature-contracts.md` §2b).

## What to build

1. Add cases that pin containment on every side: a rect flush with each edge is accepted; the same rect moved one tile further out is refused, on the right, the bottom, the left and the top; a rect wider or taller than the whole grid is refused; a rect at a negative coordinate is refused.
2. Name them in the existing `G<n>` sequence, continuing from the highest one already there.
3. Plant the defect yourself to prove the new case fails with it and passes without it, and paste both runs.

## What done mean

```checks
{"name": "grid_bounds-tests", "command": "lua5.2 tests/test_grid.lua && lua5.4 tests/test_grid.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-1-candidate --manifest docs/tasks/013.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the new case failing against the planted defect, then passing once the defect is reverted.
- `git diff --stat wave-1-candidate HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit made afterwards moves the tree the proof
was taken against, and the supervisor refuses that proof with the reason `tree-moved`.

## Files this lane owns

- `logic/bp/grid.lua`
- `tests/test_grid.lua`

Touch nothing else.

# bound: 3600s

Reviewer ask: does a rect one tile past each of the four edges fail, and is a flush rect still accepted?
