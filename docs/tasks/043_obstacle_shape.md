# 043 — the packer gets rectangles, the power stage gets owners

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-043`, branch `lane/043`, base = `feat/round-8-blueprints`, tag `recovery-base` (resolve it with `git rev-parse recovery-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane, highest priority: this defect is the first thing that breaks when a real sheet is generated, and it
blocks lane 039, which owns the generation service.

## What is true

**PRESERVE:**
- You own `logic/bp/search.lua` and `tests/test_search.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report. `logic/bp/pack.lua`, `logic/bp/grid.lua` and `logic/bp/power.lua` are **not** yours: the two shapes they take are both correct, and the caller is what mixes them.
- Every existing case stays. Bound every wait at 600 iterations and fail the case naming the phase it stopped in.
- `require` runs only while `control.lua` is parsed. Never call it inside a function.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts, reproduced on this base:
- `logic/bp/search.lua:177` builds each roboport obstacle as `{rect = {x, y, w, h}, owner = id}`. That is the shape `logic/bp/power.lua` wants for `occupied`, and `occupied_rects` at `logic/bp/search.lua:271-273` passes it there correctly.
- `logic/bp/search.lua:503-506` hands the **same** list to `Pack.begin{area = ..., obstacles = ...}`. The packer documents `obstacles = {TileRect}` at `logic/bp/pack.lua:6`, and `copy_rects` at `:146` reads `x`, `y`, `w`, `h` straight off each entry. Those are all nil in a `{rect, owner}` record.
- The result is `logic/bp/grid.lua:73: attempt to compare number with nil`, raised from `Grid.free_regions` on the first layout tick of a real sheet. `tests/test_search.lua` never sees it, because its fixtures reach Pack through inputs that carry no roboport obstacle.
- The same mixed list reaches `make_route_input` at `logic/bp/search.lua:296,327`; check which shape the router reads and fix that call too if it disagrees.

## What to build

1. Keep one authoritative list of roboport obstacles with owners, and hand each consumer the shape it documents: bare `TileRect` values to `Pack.begin`, `{rect, owner}` records to the power stage, and whatever the router documents to the router.
2. Add a case that drives the real seam: an input carrying roboports, a plan with at least one step, run to a placement, asserting that the placements avoid every roboport rectangle and that no error is raised.
3. Add a case that the power stage still receives owners for those same roboports, so a future change cannot fix one consumer by breaking the other.
4. Add a case for the router's shape, matching whatever it documents.
5. Name them in the existing `BP-15` and `BP-20` clause style with a distinct tail.
6. Plant the defect yourself — put the `{rect, owner}` records back into the `Pack.begin` call — paste the new case red with the `grid.lua:73` failure tagged as an assertion, then green.

## What done mean

```checks
{"name": "search-tests", "command": "lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "algorithm-neighbours", "command": "lua5.2 tests/test_pack.lua && lua5.2 tests/test_power.lua && lua5.2 tests/test_route.lua && lua5.2 tests/test_grid.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base recovery-base --manifest docs/tasks/043.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the red run showing the `grid.lua:73` failure, then the green run.
- `git diff --stat recovery-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `logic/bp/search.lua`
- `tests/test_search.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does a search over a grid that holds roboports reach a placement without raising?
