# 075 — Placed boxes never overlap, and a small plan still publishes

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-075`, branch `lane/075`, base tag `validator-rejection-4-base` (resolve with `git rev-parse validator-rejection-4-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/groups.lua`, `logic/bp/pack.lua`, `tests/test_groups.lua`, `tests/test_pack.lua` and new `tests/test_placement_boxes.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/route.lua`, `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- **`tests/test_search.lua` must stay green.** It is frozen, and it is the gate that caught the last attempt.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**Write `tests/test_placement_boxes.lua` first, before changing any module.**

Commit `0c4caa6` on branch `lane/074` is unmerged work at this exact problem. Read it with `git show 0c4caa6`.
Its regression test is good; take it. Its module change is **refused**, and here is why, measured host
`legalcopilot-dev`, 2026-09-20:

- It drove `BP_V_COLLISION` 18, `BP_V_BEACON_COVERAGE_SHORT` 21 and `BP_V_PORT_EDGE_WRONG` 21 all to zero, and
  cut the fixture's 20000-tick run from about six minutes to 50 s.
- It also reserved each placed block's envelope for routing, and that made plans that used to publish fail:
  `tests/test_search.lua` lost 48 cases, including `BP-15 a small feasible plan publishes a validated blueprint`
  and `BP-15 a real small plan serializes with in-grid perimeter ports`, the latter with
  `BP_FAIL_NO_LAYOUT_GRID_LIMIT`.

A one-tile ring around every block was refused once before for the same reason. Reserving space a block does not
occupy is not available to you.

Measured counts on this base, twelve grid trials on `docs/tasks/058_reproducer.lua`, host `legalcopilot-dev`,
2026-09-20:

```text
BP_V_BEACON_COVERAGE_SHORT  21
BP_V_COLLISION              18
BP_V_PORT_EDGE_WRONG        21
```

Run it yourself and read the `DETAIL` lines:

```sh
timeout 800 lua5.2 docs/tasks/058_reproducer.lua
```

## What to build

Drive `BP_V_COLLISION` to zero **without reserving any tile a block does not occupy**. Machines, inserters and
beacons each carry their own rectangle, and `Grid.place_member` rotates each one; the block envelope is not an
entity box. Find which two entity kinds overlap, and in which direction, before changing arithmetic. Leave the
other two codes alone; they are separate tasks.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout validator-rejection-4-base -- logic/bp/groups.lua logic/bp/pack.lua; out=$(cd \"$S\" && lua5.2 tests/test_placement_boxes.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_groups.lua && lua5.4 tests/test_groups.lua && lua5.2 tests/test_pack.lua && lua5.4 tests/test_pack.lua && lua5.2 tests/test_placement_boxes.lua && lua5.4 tests/test_placement_boxes.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "search-stays-green", "command": "lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua && lua5.2 tests/test_search_budget.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "validator-untouched", "command": "git diff --name-only validator-rejection-4-base HEAD | grep -qE '^logic/bp/(validate|serialize|route|search|power)\\.lua$' && exit 1; echo validator-untouched", "expect_exit": 0, "expect_regex": "validator-untouched", "timeout_s": 120}
{"name": "no-collision", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_COLLISION' && exit 1; echo no-collision", "expect_exit": 0, "expect_regex": "no-collision", "timeout_s": 900}
{"name": "fixture-still-terminates", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=(failure|success)' && echo fixture-terminates", "expect_exit": 0, "expect_regex": "fixture-terminates", "timeout_s": 900}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_port_edges.lua && lua5.2 tests/test_route.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base validator-rejection-4-base --manifest docs/tasks/075.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

## Files this lane owns

`logic/bp/groups.lua`, `logic/bp/pack.lua`, `tests/test_groups.lua`, `tests/test_pack.lua`, `tests/test_placement_boxes.lua`.

# bound: 1918s
