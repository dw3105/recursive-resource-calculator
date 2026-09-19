# 032 — an edge is legal only within the shorter pole's reach

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-032`, branch `lane/032`, base = `feat/round-8-blueprints`, tag `wave-3-validate-base` (resolve it with `git rev-parse wave-3-validate-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane. A mutation batch planted a defect in `logic/bp/validate.lua` and all thirteen validator cases stayed green, so that behaviour has no case.

## What is true

**PRESERVE:**
- You own `logic/bp/validate.lua` and `tests/test_validate.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_validate.lua` stays. You add; you never weaken or delete.
- `prototypes`, `game`, `settings` and every prototype list are **userdata** in the game, never tables. Never write `type(prototypes) == "table"`; ask `rawget(_G, "prototypes")` instead (`docs/feature-contracts.md` §2c).
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- The planted defect: `logic/bp/validate.lua:624` is `local reach = reason and nil or math.min(wire_reach(a, work.catalog) or 0, wire_reach(b, work.catalog) or 0)`. Changing `math.min` to `math.max` keeps every case green.
- Why nothing fails: the only wire fixtures are V6 at `tests/test_validate.lua:103` and V8 at `:122`, and both place two poles of the same prototype `pole` with no quality, so `wire_reach` returns the same number for each end and `min` equals `max`. No fixture holds two ends of different reach.
- `wire_reach(info, catalog)` at `logic/bp/validate.lua:348-351` reads `entity.wire_reach` first, then `info.spec.wire_reach`, then `catalog.pole.wire_reach`. The fixture catalog at `tests/test_validate.lua:28` sets `pole = {wire_reach = 2, supply_w = 0, supply_h = 0}`, so a per-entity `wire_reach` on one pole is enough to build a mixed pair.
- BP-13 is the clause: reach is measured at **each pole's own quality**, and the shorter of the two governs the edge. `logic/bp/power.lua` proves the same rule for the builder in case BP4; the validator must prove it independently, because a checker sharing the builder's model cannot catch the builder's mistake.
- Legality is recorded before connectivity, and only edges that passed build the graph: `logic/bp/validate.lua:617-632`, codes `BP_V_WIRE_ILLEGAL` then `BP_V_WIRE_DISCONNECTED`.
- Assert a value exists before reading it, so a failure is an assertion and not a nil index (`docs/feature-contracts.md` §2b).

## What to build

1. Add a case with two poles of **different** reach, placed at a distance the longer reach covers and the shorter one does not: the edge is `BP_V_WIRE_ILLEGAL` with reason `over range`, and it is excluded from connectivity.
2. Add a case with the same pair placed inside the **shorter** reach: the edge is legal and the poles form one component.
3. Add a boundary case at exactly the shorter reach: legal, since the check allows the distance plus tolerance.
4. Assert in the first case that the reported reason names the range, so a future change cannot pass by reporting a different reason.
5. Name them in the existing `V<n>` sequence.
6. Plant the defect yourself, paste each new case red, then paste them green with the defect reverted.

## What done mean

```checks
{"name": "validate-tests", "command": "lua5.2 tests/test_validate.lua && lua5.4 tests/test_validate.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-3-validate-base --manifest docs/tasks/032.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste each new case failing against the planted defect, then passing once the defect is reverted.
- `git diff --stat wave-3-validate-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `logic/bp/validate.lua`
- `tests/test_validate.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does a pair of poles of different reach, bridged beyond the shorter one, turn a named case red?
