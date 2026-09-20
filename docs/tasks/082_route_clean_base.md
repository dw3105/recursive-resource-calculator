# 082 — The clean layout finds its routes

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-082`, branch `lane/082`, base tag `clean-base-route` (resolve with `git rev-parse clean-base-route`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/route.lua`, `logic/bp/search.lua`, `tests/test_route.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua` and new `tests/test_external_ports.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- **These must stay green:** `tests/test_blueprint_pipeline.lua`, `tests/test_validate.lua`, `tests/test_route_layout_contract.lua`, `tests/test_port_edges.lua`, `tests/test_port_tile_flow.lua`, `tests/test_port_not_self_blocked.lua`, `tests/test_route_footprints.lua`, `tests/test_underground_pairs.lua`, `tests/test_beacon_coverage.lua`, `tests/test_route_budget.lua`, `tests/test_pack.lua`, `tests/test_groups.lua`.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**Write `tests/test_external_ports.lua` first, before changing any module.**

This base is clean and fast. On the player's fixture the validator rejects nothing at all, the run is terminal in
seconds, and the only thing missing is a route, measured host `legalcopilot-dev`, 2026-09-20, twelve grid trials:

```text
DISCARD route  24
ROUTECODE BP_R_NO_PATH    flow=item/plate    14
ROUTECODE BP_R_NO_PATH    flow=item/machine   5
ROUTECODE BP_R_EXPANSIONS flow=item/cable     5
```

`item/plate` is supplied from outside and feeds **three** steps, and `generated_perimeter_ports` in
`logic/bp/search.lua:484` gives each plan port exactly one perimeter slot. One belt from one edge tile must then
serve three consumers on its own, through a grid where every port already owns its tile and its approach tile.
That is where fourteen of the twenty-four failures come from.

Two attempts to solve this by changing the block layout were refused: a corridor candidate routed more
candidates and then failed validation on `BP_V_UNDERGROUND_RANGE`, `BP_V_PORT_EDGE_WRONG`, `BP_V_COLLISION` and
`BP_V_BEACON_COVERAGE_SHORT`, nine candidates out of nine. Do not change the block layout. Work on the external
ports and the paths.

Run the fixture yourself; it costs seconds:

```sh
timeout 300 lua5.2 docs/tasks/058_reproducer.lua
```

## What to build

Give an external flow as many perimeter ports as its consumers need, instead of one per plan port, and let a
demand pick the port that can reach it. Keep them deterministic and bounded: a fixed pitch along the edge, a
fixed order, and a cap so a sheet cannot ask for more ports than the edge has slots. A shared trunk is still
allowed and still preferred when it fits.

Never reserve a tile a block does not occupy; that was refused twice on this branch.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout clean-base-route -- logic/bp/route.lua logic/bp/search.lua; out=$(cd \"$S\" && lua5.2 tests/test_external_ports.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua && lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua && lua5.2 tests/test_search_budget.lua && lua5.2 tests/test_external_ports.lua && lua5.4 tests/test_external_ports.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "everything-else-stays-green", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_route_layout_contract.lua && lua5.2 tests/test_port_edges.lua && lua5.2 tests/test_port_tile_flow.lua && lua5.2 tests/test_port_not_self_blocked.lua && lua5.2 tests/test_route_footprints.lua && lua5.2 tests/test_underground_pairs.lua && lua5.2 tests/test_beacon_coverage.lua && lua5.2 tests/test_route_budget.lua && lua5.2 tests/test_pack.lua && lua5.2 tests/test_groups.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "fixture-terminates-in-300s", "command": "out=$(timeout 300 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=(failure|success)' && echo fixture-terminates", "expect_exit": 0, "expect_regex": "fixture-terminates", "timeout_s": 500}
{"name": "validator-clean", "command": "out=$(timeout 300 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_' && exit 1; echo validator-clean", "expect_exit": 0, "expect_regex": "validator-clean", "timeout_s": 500}
{"name": "fixture-reaches-success", "command": "out=$(timeout 300 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=success' && echo fixture-success", "expect_exit": 0, "expect_regex": "fixture-success", "timeout_s": 500}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base clean-base-route --manifest docs/tasks/082.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_external_ports.lua` must cover: one external flow with three consumers receiving enough ports; a
shared trunk still chosen when one port reaches every consumer; an edge with too few slots reporting a bounded
failure rather than stacking two ports on one tile; and the same input giving the same ports twice in a row.

If `fixture-reaches-success` stays out of reach, commit what you have with its test and report the exact
remaining route codes with their counts.

## Files this lane owns

`logic/bp/route.lua`, `logic/bp/search.lua`, `tests/test_route.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua`, `tests/test_external_ports.lua`.

# bound: 1918s
