# 029 — the packer picks the tighter region, and refuses a region that fits on one axis only

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-029`, branch `lane/029`, base = `feat/round-8-blueprints`, tag `wave-3-repair-base` (resolve it with `git rev-parse wave-3-repair-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane. A mutation batch planted two defects in `logic/bp/pack.lua` and every one of the nine pack cases stayed green, so neither behaviour has a case.

## What is true

**PRESERVE:**
- You own `logic/bp/pack.lua` and `tests/test_pack.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_pack.lua` stays. You add; you never weaken or delete.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- Defect 1: `logic/bp/pack.lua:87` is `if candidate.short_side ~= best.short_side then return candidate.short_side < best.short_side end`. Flipping `<` to `>` turns best-short-side-fit into worst-short-side-fit and nothing fails.
  Why nothing fails: `tests/test_pack.lua:154` P9 uses `area = Grid.rect(0, 0, 10, 8)` with one obstacle `Grid.rect(0, 3, 10, 2)`, so the two free regions are `(0,0,10,3)` and `(0,5,10,3)`. Both are 10 by 3, so both score the same short side for the 3 by 3 block, and the `x` then `y` tie-break at `logic/bp/pack.lua:89-90` decides. The case never compares two different short sides.
- Defect 2: `logic/bp/pack.lua:97` is `if region.w >= w and region.h >= h then`. Changing `and` to `or` lets a block enter a region that fits on one axis only, and nothing fails.
  Why nothing fails: `tests/test_pack.lua:70` P2 uses a 10 by 10 area with one 2 by 2 obstacle at `(4,4)`, and its blocks are 3 by 3, 3 by 3 and 2 by 4. Every free region in that fixture is at least 4 wide and 4 high, so no region ever fails one axis while passing the other.
- `Pack.bssf_score(region, w, h)` at `logic/bp/pack.lua:203-206` returns `math.min(leftover_w, leftover_h), math.max(leftover_w, leftover_h)`, i.e. short side then long side.
- The packing model is the integer tile bound of `docs/feature-contracts.md` §5.1. A placement that leaves the area or overlaps an obstacle is a packer defect, not something a later stage repairs.
- Assert a value exists before reading it, so a failure is an assertion and not a nil index (`docs/feature-contracts.md` §2b).

## What to build

1. Add a case where two free regions have **different** short-side scores for the same block, and assert the block lands in the tighter one. Build it so the looser region wins every tie-break at `logic/bp/pack.lua:89-91` (smaller `x`, smaller `y`, smaller `dir`), so only the short-side comparison can place the block correctly.
2. Add a case where the long side decides: two regions with equal short side and different long side, block in the tighter one.
3. Add a case with a region that fits the block on one axis only, for example a 2 wide by 8 high corridor beside a 5 by 5 open area with a 3 by 3 block, and assert the placement sits in the open area, stays inside the packing area, and never overlaps an obstacle.
4. Add a case where **no** region fits on both axes although one axis fits everywhere, and assert `BP_P_NO_FIT` naming the block, per `logic/bp/pack.lua:108`.
5. Name them in the existing `P<n>` sequence.
6. Plant each defect yourself, paste the new case red, then paste it green with the defect reverted.

## What done mean

```checks
{"name": "pack-tests", "command": "lua5.2 tests/test_pack.lua && lua5.4 tests/test_pack.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-3-repair-base --manifest docs/tasks/029.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste each new case failing against its planted defect, then passing once the defect is reverted.
- `git diff --stat wave-3-repair-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `logic/bp/pack.lua`
- `tests/test_pack.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does a flipped short-side comparison, and an `and` turned into `or` at the fit test, each turn a named case red?
