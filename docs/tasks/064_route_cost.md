# 064 — A failing route costs a fraction of a full grid sweep

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-064`, branch `lane/064`, base tag `route-cost-base` (resolve with `git rev-parse route-cost-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua` and `tests/fixtures/routing/`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `tests/fixtures/routing/player_chain_first_candidate.lua` is a frozen positive input. Never edit it.
- Every existing case stays green: `tests/test_route.lua` 34, `tests/test_route_budget.lua` 8.
- `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/pack.lua`, `logic/bp/groups.lua`, `logic/bp/validate.lua` have other owners. Never edit them.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Measured on this base, host `legalcopilot-dev`, 2026-09-19, whole fixture `docs/tasks/058_reproducer.lua`, 1200 ticks at `OPS_PER_TICK = 2000`:

```text
PROF route  calls=1207  ops=2329281  time=33.62
PROF power  calls=42    ops=68496    time=3.95
PROF pack   calls=47    ops=642      time=1.93
ops charged by site: search 2329269, exp_limit 12
route runs: 45 total, 7 ok, 26 BP_R_NO_PATH, 12 BP_R_EXPANSIONS
frozen input alone: done=true ok=true ops=10644 restarts=1
```

Read those two lines together. One routing run may spend `max_expansions = max(4096, w * h * 16)` = 46656
expansions on this 54 by 54 grid, and the search starts 45 runs, so 45 x 46656 is the whole 2.3 million. The
per-run bound holds; the cost is that a **hopeless run still pays the full sweep**, while the run that succeeds
costs 10644.

Sixteen visits per cell is four times what four direction orders can need: a breadth-first sweep visits each of
the 2916 cells once per order, which is 11664.

## What to build

Make a failing route cheap, without making a routable one fail.

1. Bound a single demand's search by what it can reach, not by the whole grid. A window around source and sink
   that widens on failure, a goal-directed frontier, or an early proof that the sink's approach tile is
   unreachable are all allowed. A cost model that assumes one-tile moves is wrong here: a crossing skips several
   tiles in one step.
2. Derive `max_expansions` from the work a sweep can need, never from a guessed multiplier.
3. Keep every behaviour that holds today: shared trunks by flow, residual capacity, port approach reservation,
   underground ends and range, separate fluid networks, one expansion budget across retries and restarts.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout route-cost-base -- logic/bp/route.lua; out=$(cd \"$S\" && lua5.2 tests/test_route_budget.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua && lua5.2 tests/test_route_budget.lua && lua5.4 tests/test_route_budget.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "frozen-input-routes", "command": "lua5.2 -e 'local i = dofile(\"tests/fixtures/routing/player_chain_first_candidate.lua\"); local R = require \"logic.bp.route\"; local s = R.begin(i); local n = 0; while not s.done and n < 4000000 do local b = {ops = 20000}; R.step(s, b); n = n + (20000 - b.ops) end; assert(s.done and s.ok, \"frozen input must route\"); print(\"frozen ok ops=\" .. n)'", "expect_exit": 0, "expect_regex": "frozen ok", "timeout_s": 300}
{"name": "hopeless-route-is-cheap", "command": "lua5.2 tests/test_route_budget.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 600}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base route-cost-base --manifest docs/tasks/064.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Add to `tests/test_route_budget.lua`: a hopeless input on a large grid whose terminal failure costs a bounded and
asserted number of expansions, far below one sweep of that grid; and the frozen input still routing inside an
asserted op bound you measure yourself. Never assert host wall-clock time.

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/fixtures/routing/`.

# bound: 1918s
