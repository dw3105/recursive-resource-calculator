# 060 — Routing does bounded, measured work on the frozen input

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-060`, branch `lane/060`, base tag `routing-recovery-base` (resolve with `git rev-parse routing-recovery-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/route.lua`, `tests/test_route.lua`, new `tests/test_route_budget.lua`, and new files under `tests/fixtures/routing/`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `tests/fixtures/routing/player_chain_first_candidate.lua` is a frozen `Route.begin` input, captured from the player's sheet shape. Its expected outcome is **success**. Never edit it, never turn it into a rejection case.
- Every existing case in `tests/test_route.lua` stays green, including `R15`, `R16` and `R17`.
- `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/pack.lua` and `logic/bp/groups.lua` have other owners. Never edit them.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- `tests/test_companion_api_shapes.lua` is red on this base, by design: it names three companion calls another lane repairs. Ignore it. Never run the whole suite as your gate.

Measured on this base, host `legalcopilot-dev`, 2026-09-19:

```text
frozen input replayed directly: done=true ok=true ops=10644 cpu=0.1s
whole fixture, 1200 ticks at OPS_PER_TICK = 2000:
  PROF route  calls=1180  ops=2295680  time=29.95
  PROF power  calls=64    ops=102436   time=61.27
  PROBE route failed code=BP_R_NO_PATH flow=item/plate
```

So the frozen candidate routes in 10644 ops, while routing across all candidates spends 2295680 ops and never
finishes. The cost is in the candidates that fail, not in the one that succeeds. A failing demand sweeps up to
`max_expansions = max(4096, w * h * 16)` = 46656 cells, once per direction order, and a rip-up restart resets
`work.expansions` to 0, so the total work of one `Route` run is not bounded by that number at all.

`logic/bp/route.lua:1018` is `Route.begin`; the retry and restart logic is at the end of `Route.step`.

## What to build

1. **Counters first, algorithm second.** Add deterministic counters to the route state: expansions, demands
   attempted, restarts, crossings placed, searches abandoned per reason. Expose them on the state so a test can
   assert them. Do not change the algorithm in the same commit.
2. **Bound the total.** One `Route` run must have one expansion budget across every direction-order retry and
   every demand-order restart. Reaching it reports `BP_R_EXPANSIONS`, which is a budget outcome, never a proof
   that the sheet is unsupported.
3. **Cut the dominant cost with the smallest measured change.** A goal-directed frontier, a bounded window that
   widens on failure, or removal of repeated sweeps are all allowed. A cost model that assumes one-tile moves is
   wrong here: a crossing skips several tiles in one step. Shortest paths are not the requirement; valid
   capacity-preserving routes and bounded deterministic work are.
4. Keep every behaviour that already holds: shared trunks by flow, residual capacity, port approach reservation,
   underground ends and range, separate fluid networks.

## What done mean

```checks
{"name": "red proof", "run": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout routing-recovery-base -- logic/bp/route.lua; out=$(cd \"$S\" && lua5.2 tests/test_route_budget.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok"}
{"name": "route green 5.2", "run": "lua5.2 tests/test_route.lua"}
{"name": "route green 5.4", "run": "lua5.4 tests/test_route.lua"}
{"name": "budget green 5.2", "run": "lua5.2 tests/test_route_budget.lua"}
{"name": "budget green 5.4", "run": "lua5.4 tests/test_route_budget.lua"}
{"name": "frozen input still routes", "run": "lua5.2 -e 'local i = dofile(\"tests/fixtures/routing/player_chain_first_candidate.lua\"); local R = require \"logic.bp.route\"; local s = R.begin(i); local n = 0; while not s.done and n < 4000000 do local b = {ops = 20000}; R.step(s, b); n = n + (20000 - b.ops) end; assert(s.done and s.ok, \"frozen input must route\"); print(\"frozen ok ops=\" .. n)'"}
{"name": "pipeline gate", "run": "timeout 900 lua5.2 tests/test_blueprint_pipeline.lua"}
{"name": "ownership", "run": "python3 tools/lane_ownership.py --base routing-recovery-base --manifest docs/tasks/060.manifest"}
```

`tests/test_route_budget.lua` must contain, at least:

- The frozen input routes, and the op count it takes is asserted against a bound you derive from your own
  measurement. Never assert host wall-clock time.
- Two tick slice sizes, for example `{ops = 1}` and `{ops = 10^6}`, reach the same committed result.
- A deliberately unroutable input reports `BP_R_EXPANSIONS` or `BP_R_NO_PATH` after a bounded number of
  expansions, and the counter proves the bound held across restarts.
- A cancelled run leaves no half-written segment list.

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/fixtures/routing/`.

# bound: 2400s
