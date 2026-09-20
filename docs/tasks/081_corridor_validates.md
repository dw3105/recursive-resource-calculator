# 081 — The corridor candidate routes and validates

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-081`, branch `lane/081`, base tag `corridor-base` (resolve with `git rev-parse corridor-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/route.lua`, `tests/test_groups.lua`, `tests/test_pack.lua`, `tests/test_route.lua` and new `tests/test_first_layout.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- **These must stay green:** `tests/test_search.lua`, `tests/test_blueprint_pipeline.lua`, `tests/test_validate.lua`, `tests/test_route_layout_contract.lua`, `tests/test_port_edges.lua`, `tests/test_port_tile_flow.lua`, `tests/test_port_not_self_blocked.lua`, `tests/test_route_footprints.lua`, `tests/test_underground_pairs.lua`, `tests/test_beacon_coverage.lua`, `tests/test_route_budget.lua`, `tests/test_placement_boxes.lua` if present.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Commit `8749840` on branch `lane/080` is unmerged work at this exact problem. Read it with `git show 8749840`.
It adds a corridor candidate whose machines sit in rows with belt space between them, and it is the first change
on this branch that got candidates **past routing**. Take it as your starting point; never merge that branch.

Measured on this base, host `legalcopilot-dev`, 2026-09-20:

```text
this base            DISCARD route 24, validate 0, validator rejections 0
lane/080 commit      DISCARD route 14, validate 4, VALIDATE ok=0 bad=4
lane/080 codes       BP_V_PORT_EDGE_WRONG, BP_V_BEACON_COVERAGE_SHORT, 4 candidates each
```

So the corridor shape routes, and then every one of its candidates is refused by the validator for two codes
this branch had already driven to zero on the compact shapes. Its rows put ports and beacons where the placed
geometry no longer matches what the validator reads.

It is also slow: 3000 ticks cost about four minutes, and 40000 ticks did not finish inside 700 seconds.

Run the fixture yourself:

```sh
timeout 500 lua5.2 docs/tasks/058_reproducer.lua
```

## What to build

1. Keep the corridor candidate, and make its placed ports satisfy the validator's edge rule and its placed
   beacons cover the machines that ask for them, exactly as the compact shapes already do.
2. Keep the compact candidates unchanged; a sheet that already routes must keep routing.
3. Never reserve a tile globally. A one-tile ring around every block and a whole placed envelope were both
   refused on this branch; the second cost `tests/test_search.lua` 48 cases.
4. Bring the cost back: the fixture must reach a terminal result inside 500 seconds.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout corridor-base -- logic/bp/groups.lua logic/bp/pack.lua logic/bp/route.lua; out=$(cd \"$S\" && lua5.2 tests/test_first_layout.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_groups.lua && lua5.4 tests/test_groups.lua && lua5.2 tests/test_pack.lua && lua5.4 tests/test_pack.lua && lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua && lua5.2 tests/test_first_layout.lua && lua5.4 tests/test_first_layout.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "everything-else-stays-green", "command": "lua5.2 tests/test_search.lua && lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_route_layout_contract.lua && lua5.2 tests/test_port_edges.lua && lua5.2 tests/test_port_tile_flow.lua && lua5.2 tests/test_port_not_self_blocked.lua && lua5.2 tests/test_route_footprints.lua && lua5.2 tests/test_underground_pairs.lua && lua5.2 tests/test_beacon_coverage.lua && lua5.2 tests/test_route_budget.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "fixture-terminates-in-500s", "command": "out=$(timeout 500 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=(failure|success)' && echo fixture-terminates", "expect_exit": 0, "expect_regex": "fixture-terminates", "timeout_s": 700}
{"name": "validator-clean", "command": "out=$(timeout 500 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_' && exit 1; echo validator-clean", "expect_exit": 0, "expect_regex": "validator-clean", "timeout_s": 700}
{"name": "fixture-reaches-success", "command": "out=$(timeout 500 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=success' && echo fixture-success", "expect_exit": 0, "expect_regex": "fixture-success", "timeout_s": 700}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base corridor-base --manifest docs/tasks/081.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

If `fixture-reaches-success` stays out of reach, commit what you have with its test and report exactly which
demand or which validator code still stands, with the counts.

## Files this lane owns

`logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/route.lua`, `tests/test_groups.lua`, `tests/test_pack.lua`, `tests/test_route.lua`, `tests/test_first_layout.lua`.

# bound: 1918s
