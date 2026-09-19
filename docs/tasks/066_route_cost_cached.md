# 066 — Proving a route hopeless must cost less than trying it

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-066`, branch `lane/066`, base tag `route-cost-2-base` (resolve with `git rev-parse route-cost-2-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua` and `tests/fixtures/routing/`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `tests/fixtures/routing/player_chain_first_candidate.lua` is a frozen positive input. Never edit it.
- `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/pack.lua`, `logic/bp/groups.lua`, `logic/bp/validate.lua`, `logic/bp/serialize.lua` have other owners. Never edit them.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Commit `19d75d6` on branch `lane/064` is finished work that passed every focused gate and was **refused at
integration**. Read it with `git show 19d75d6 -- logic/bp/route.lua`. Reuse what is sound; never merge that
branch.

What it got right: a reachability proof. Before sweeping, it builds the connected component of the demand's
source under the same free-cell predicate the search uses, including crossings, and fails the demand at once when
the sink is outside it. It also derives `max_expansions` from reachable cells times four directions times four
direction orders, instead of the guessed `w * h * 16`.

Why it was refused, measured host `legalcopilot-dev`, 2026-09-19, `docs/tasks/058_reproducer.lua`, 300 ticks:

```text
lane/064 tree                   89.98 s
feat/round-8-blueprints tree    18.39 s
```

Its `static_component` is cached; its `current_component` is not. `current_component` sweeps the whole grid on
every `begin_search`, so proving one demand hopeless costs a full sweep, which is the very cost the probe exists
to avoid. Its own gates never saw this: they run one input, never the whole fixture.

## What to build

Keep the reachability proof and the derived limit. Make the proof cheap.

1. The component of a source must be computed once per set of blocking facts, never once per search start. A
   component invalidated only when a segment is added, a demand list is reordered, or a restart rips the grid out
   is enough. Incremental reuse is allowed; recomputing every call is not.
2. Proving a demand hopeless must cost strictly less than one sweep of the cells that demand can reach. Assert
   that with a counter, never with host wall-clock time.
3. Keep every behaviour that holds today: shared trunks by flow, residual capacity, port approach reservation,
   underground ends and range, separate fluid networks, one cumulative expansion budget across retries and
   restarts, and the frozen input routing in about 10644 ops.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout route-cost-2-base -- logic/bp/route.lua; out=$(cd \"$S\" && lua5.2 tests/test_route_budget.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua && lua5.2 tests/test_route_budget.lua && lua5.4 tests/test_route_budget.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "frozen-input-routes", "command": "lua5.2 -e 'local i = dofile(\"tests/fixtures/routing/player_chain_first_candidate.lua\"); local R = require \"logic.bp.route\"; local s = R.begin(i); local n = 0; while not s.done and n < 4000000 do local b = {ops = 20000}; R.step(s, b); n = n + (20000 - b.ops) end; assert(s.done and s.ok); print(\"frozen ok ops=\" .. n)'", "expect_exit": 0, "expect_regex": "frozen ok", "timeout_s": 300}
{"name": "whole-fixture-300-ticks", "command": "S=$(mktemp -d); cp -r logic gui tests docs *.lua \"$S\"/; sed -i 's/for _ = 1, 1200 do/for _ = 1, 300 do/' \"$S\"/docs/tasks/058_reproducer.lua; start=$(date +%s); (cd \"$S\" && timeout 200 lua5.2 docs/tasks/058_reproducer.lua >/dev/null 2>&1); stop=$(date +%s); rm -rf \"$S\"; elapsed=$((stop - start)); echo \"fixture-300-ticks ${elapsed}s\"; [ \"$elapsed\" -le 40 ]", "expect_exit": 0, "expect_regex": "fixture-300-ticks", "timeout_s": 300}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base route-cost-2-base --manifest docs/tasks/066.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

The 300-tick check is an integration guard, not a unit assertion: the base tree takes 18 s and the refused work
took 90 s, so 40 s is a wide margin. Keep every unit assertion on counters.

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/fixtures/routing/`.

# bound: 1918s
