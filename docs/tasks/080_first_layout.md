# 080 — One candidate that leaves room for the belts

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-080`, branch `lane/080`, base tag `first-layout-base` (resolve with `git rev-parse first-layout-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/route.lua`, `tests/test_groups.lua`, `tests/test_pack.lua`, `tests/test_route.lua` and new `tests/test_first_layout.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- **These must stay green, all of them:** `tests/test_search.lua`, `tests/test_blueprint_pipeline.lua`, `tests/test_validate.lua`, `tests/test_route_layout_contract.lua`, `tests/test_port_edges.lua`, `tests/test_port_tile_flow.lua`, `tests/test_port_not_self_blocked.lua`, `tests/test_route_footprints.lua`, `tests/test_underground_pairs.lua`, `tests/test_beacon_coverage.lua`, `tests/test_route_budget.lua`.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**Write `tests/test_first_layout.lua` first, before changing any module.**

The validator now rejects nothing on the player's fixture. Every code that once fired is zero: collisions, wires,
underground pairing, port edges, beacon coverage. The fixture costs seconds instead of minutes. What remains is
that no candidate can be routed at all, measured host `legalcopilot-dev`, 2026-09-20, twelve grid trials:

```text
DISCARD route  24
ROUTECODE BP_R_NO_PATH    flow=item/plate    14
ROUTECODE BP_R_NO_PATH    flow=item/machine   5
ROUTECODE BP_R_EXPANSIONS flow=item/cable     5
```

Run it yourself; it is fast now:

```sh
timeout 300 lua5.2 docs/tasks/058_reproducer.lua
```

`item/plate` arrives from one external perimeter port and feeds three steps. The packer places blocks compactly,
by MaxRects, and transport space is whatever happens to be left over. On this sheet what is left over is not
enough.

## What to build

Add **one extra candidate shape** whose machines are laid out in rows with a belt corridor between them, and
offer it beside the compact ones. Transport space becomes an input to placement rather than a leftover.

Hard limits, learned from two refused attempts on this branch:

- Never reserve a tile globally. Reserving a one-tile ring around every block, and reserving each placed block's
  envelope, were both refused: each made plans that used to publish fail, and `tests/test_search.lua` lost 48
  cases the second time.
- The corridor shape is an **additional** candidate. Compact candidates stay exactly as they are, and a sheet
  that already routes must keep routing.
- A wider layout is acceptable. A few extra belts are acceptable. Missing power, short beacon coverage, an
  overlapping box or a sheet that used to publish and no longer does are never acceptable.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout first-layout-base -- logic/bp/groups.lua logic/bp/pack.lua logic/bp/route.lua; out=$(cd \"$S\" && lua5.2 tests/test_first_layout.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_groups.lua && lua5.4 tests/test_groups.lua && lua5.2 tests/test_pack.lua && lua5.4 tests/test_pack.lua && lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua && lua5.2 tests/test_first_layout.lua && lua5.4 tests/test_first_layout.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "everything-else-stays-green", "command": "lua5.2 tests/test_search.lua && lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_route_layout_contract.lua && lua5.2 tests/test_port_edges.lua && lua5.2 tests/test_port_tile_flow.lua && lua5.2 tests/test_port_not_self_blocked.lua && lua5.2 tests/test_route_footprints.lua && lua5.2 tests/test_underground_pairs.lua && lua5.2 tests/test_beacon_coverage.lua && lua5.2 tests/test_route_budget.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "fixture-reaches-success", "command": "out=$(timeout 600 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=success' && echo fixture-success", "expect_exit": 0, "expect_regex": "fixture-success", "timeout_s": 900}
{"name": "validator-still-clean", "command": "out=$(timeout 600 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_' && exit 1; echo validator-clean", "expect_exit": 0, "expect_regex": "validator-clean", "timeout_s": 900}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base first-layout-base --manifest docs/tasks/080.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

**`fixture-reaches-success` is the point of this task.** `docs/tasks/058_reproducer.lua` must print
`REPRO state=success`. If you cannot reach it, commit the corridor candidate with its test and say in your report
exactly which demand still has no path and why.

## Files this lane owns

`logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/route.lua`, `tests/test_groups.lua`, `tests/test_pack.lua`, `tests/test_route.lua`, `tests/test_first_layout.lua`.

# bound: 1918s
