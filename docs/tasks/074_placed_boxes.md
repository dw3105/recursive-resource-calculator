# 074 — No two placed boxes overlap

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-074`, branch `lane/074`, base tag `validator-rejection-3-base` (resolve with `git rev-parse validator-rejection-3-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/groups.lua`, `logic/bp/pack.lua`, `tests/test_groups.lua`, `tests/test_pack.lua` and new `tests/test_placement_boxes.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/route.lua`, `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**Write `tests/test_placement_boxes.lua` first, before changing any module.** A previous attempt at this work ran
out of its deadline with the module edited and no test written, so nothing could be merged. A failing test on
disk after twenty minutes is worth more than a finished idea at the deadline.

Scope here is **one code only**: `BP_V_COLLISION`. Beacon coverage and the residual port edges are separate
tasks; leave their counts alone and never judge yourself on them.

Measured on this base, host `legalcopilot-dev`, 2026-09-20, twelve grid trials on
`docs/tasks/058_reproducer.lua`:

```text
BP_V_BEACON_COVERAGE_SHORT  21
BP_V_COLLISION              18
BP_V_PORT_EDGE_WRONG        21
```

Run it yourself and read the `DETAIL` lines of the terminal failure:

```sh
timeout 800 lua5.2 docs/tasks/058_reproducer.lua
```

`BP_V_COLLISION` in `logic/bp/validate.lua` is exact collision-box overlap. A rotated block's envelope is not an
entity box: machines, inserters and beacons each carry their own rectangle, and `Grid.place_member` rotates each
one. A previous lane already took this count from 33 to 18, so the remaining case differs from the one fixed.
Find which two entity kinds overlap, and in which direction, before changing arithmetic.

Commit `6d0894e` on branch `lane/072` is unmerged work at this problem that ran out of time with no test. Read it
with `git show 6d0894e`. Reuse what is sound; never merge that branch. Measured with its two files applied to
this base: the fixture no longer reaches a terminal result inside 20000 ticks, so whatever it changed also costs
time. Treat it as a hint, never as a base.

## What to build

Drive `BP_V_COLLISION` to zero on the fixture, with the validator untouched and no new cost.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout validator-rejection-3-base -- logic/bp/groups.lua logic/bp/pack.lua; out=$(cd \"$S\" && lua5.2 tests/test_placement_boxes.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_groups.lua && lua5.4 tests/test_groups.lua && lua5.2 tests/test_pack.lua && lua5.4 tests/test_pack.lua && lua5.2 tests/test_placement_boxes.lua && lua5.4 tests/test_placement_boxes.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "validator-untouched", "command": "git diff --name-only validator-rejection-3-base HEAD | grep -qE '^logic/bp/(validate|serialize|route|search|power)\\.lua$' && exit 1; echo validator-untouched", "expect_exit": 0, "expect_regex": "validator-untouched", "timeout_s": 120}
{"name": "no-collision", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_COLLISION' && exit 1; echo no-collision", "expect_exit": 0, "expect_regex": "no-collision", "timeout_s": 900}
{"name": "fixture-still-terminates", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=(failure|success)' && echo fixture-terminates", "expect_exit": 0, "expect_regex": "fixture-terminates", "timeout_s": 900}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_port_edges.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base validator-rejection-3-base --manifest docs/tasks/074.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_placement_boxes.lua` checks a placed block with an independently written overlap predicate, never the
producer's helper, in each of the four directions, covering a machine beside an inserter, a beacon row above
machines, and a non-square member.

## Files this lane owns

`logic/bp/groups.lua`, `logic/bp/pack.lua`, `tests/test_groups.lua`, `tests/test_pack.lua`, `tests/test_placement_boxes.lua`.

# bound: 1918s
