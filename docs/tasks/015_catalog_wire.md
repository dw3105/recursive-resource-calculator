# 015 — a pole's wire reach follows its quality

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-015`, branch `lane/015`, base = `feat/round-8-blueprints`, tag `wave-1-candidate` (resolve it with `git rev-parse wave-1-candidate`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This is a repair lane. A mutation batch planted a defect in `logic/catalog.lua` and every test stayed green, so the module's
tests do not cover that behaviour. Close the gap.

## What is true

**PRESERVE:**
- You own `logic/catalog.lua` and `tests/test_catalog.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_catalog.lua` stays. You add; you never weaken or delete.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- The planted defect: the catalog read `entity.get_max_wire_distance("normal")` instead of the selected quality. Every one of the eleven catalog cases stayed green, although case `C2 quality accessors supply the selected pole reach` did catch the same defect in the supply area.
- Wire reach decides which pole pairs may carry power, so reading it at the wrong quality would build a network the game refuses (`docs/feature-contracts.md` §9).
- The harness's `world.add_electric_pole{name, supply_area, wire_distance, quality_affects_supply_area, supply_bonus_per_level, wire_bonus_per_level}` lets a fixture make reach differ by quality.
- Assertions are `H.equal`, `H.near`, `H.deep_equal`, `H.errors`. They tag failures `[assert]`; anything else prints `[error]` and counts as no proof.
- Assert a value exists before reading it, so a failure is an assertion and not a nil index (`docs/feature-contracts.md` §2b).

## What to build

1. Extend the fixture so a pole's wire reach differs between normal and a higher quality, and add a case asserting the catalog carries the reach of the selected quality, not the normal one.
2. Do the same for any other quality-dependent number the catalog reads and no case pins yet: crafting speed, module slots, beacon supply area, roboport radii. One case each, each failing if the accessor is called with `"normal"`.
3. Name them in the existing `C<n>` sequence.
4. Plant the defect yourself to prove the new case fails with it and passes without it, and paste both runs.

## What done mean

```checks
{"name": "catalog_wire-tests", "command": "lua5.2 tests/test_catalog.lua && lua5.4 tests/test_catalog.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-1-candidate --manifest docs/tasks/015.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the new case failing against the planted defect, then passing once the defect is reverted.
- `git diff --stat wave-1-candidate HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit made afterwards moves the tree the proof
was taken against, and the supervisor refuses that proof with the reason `tree-moved`.

## Files this lane owns

- `logic/catalog.lua`
- `tests/test_catalog.lua`

Touch nothing else.

# bound: 3600s

Reviewer ask: does every quality-dependent number in the catalog have a case that fails when it is read at normal quality?
