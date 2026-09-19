# 036 — the better layout wins, and a worse one never replaces it

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-036`, branch `lane/036`, base = `feat/round-8-blueprints`, tag `wave-4-search-base` (resolve it with `git rev-parse wave-4-search-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane. A mutation batch planted a defect in `logic/bp/search.lua` and all eight search cases stayed green, so that behaviour has no case.

## What is true

**PRESERVE:**
- You own `logic/bp/search.lua` and `tests/test_search.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_search.lua` stays. You add; you never weaken or delete.
- Bound every wait at 600 iterations and fail the case naming the phase the state stopped in. Attempt 1 of lane 026 lost its verdict to an unbounded drive loop.
- `prototypes`, `game`, `settings` and every prototype list are **userdata** in the game, never tables; ask `rawget(_G, "prototypes")`.
- `require` runs only while `control.lua` is parsed. Never call it inside a function.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- The planted defect: `logic/bp/search.lua:611` is `if state.incumbent == nil or Validate.compare(score, state.incumbent.score) < 0 then`. Flipping `<` to `>` keeps every case green, so the search may keep the **worse** layout.
- Why nothing fails: `tests/test_search.lua:103` BP-20 asserts `state.incumbent.score.beacon_count == 1`, but its fixture yields one valid candidate whose score is that one, so the comparison never chooses between two.
- `Validate.compare(a, b)` is the only ordering authority: beacon count, then footprint area, then pole count, then route length, then entity count, then a coordinate tie-break (`logic/bp/validate.lua:825-832`). It returns -1 when `a` wins.
- Ordering matters for a player: a layout with fewer beacons is what BP-20 promises, and a search that keeps the first or the worst candidate breaks that promise silently.

## What to build

1. Add a case where the search validates **two or more** candidates with different scores, and assert the incumbent is the one `Validate.compare` ranks first. Build the fixture so the better candidate is found **second**, so keeping the first is a failure.
2. Add the mirror case: the better candidate is found first and a worse one follows; the incumbent never changes.
3. Add a case for a tie on beacon count decided by the next key in the order, so a comparison that stops at the first key fails.
4. Assert in one of them the number of candidates actually validated, so a fixture that silently yields one candidate can never pass as a comparison case.
5. Name them in the existing `BP-20` clause style with a distinct tail.
6. Plant the defect yourself, paste each new case red, then green with the defect reverted.

## What done mean

```checks
{"name": "search-tests", "command": "lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-4-search-base --manifest docs/tasks/036.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste each new case red against the planted defect, then green.
- `git diff --stat wave-4-search-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `logic/bp/search.lua`
- `tests/test_search.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: when the better layout arrives second, does the search still keep it?
