# 146 guard: a routed result never publishes two entities on one tile

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-146`, branch
`lane/146`, base tag `round-16-wave3` (resolve with `git rev-parse round-16-wave3`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract `docs/feature-contracts.md` section 28. Ledger `docs/round-16-baseline.md`.
Frozen red list `docs/round-16-red-list.txt`. Frozen census `docs/round-16-census-baseline.json`.

A collision is two entities whose collision boxes overlap. Factorio refuses to place that, whatever else is
true about the layout. The validator names it `BP_V_COLLISION` at `logic/bp/validate.lua:857`.

Measured 2026-09-22 on this host, full tier, 11 validate attempts each side:

```
BP_V_COLLISION   frozen 0   ->   60
```

Cause, found and fixed on `feat/round-8-blueprints` the same day: `logic/bp/route.lua`'s splitter conversion
wrote `entity_position(cell.x + 0.5 + side_x / 2, ...)` while `entity_position` already adds half a tile per
axis, so every splitter landed **half a tile east** of its own footprint. First candidate of the player's
real sheet: `r:825` delivered `(13,9)` against a true `(12.5,9.0)`, `r:846` delivered `(11.5,41.5)` against
`(11.0,41.5)`. Three overlapping pairs in that one candidate.

**Nothing in the suite caught it.** Two tests drive `BP_V_COLLISION` and neither goes through the router:
`tests/test_validate.lua:214-221` feeds the validator two hand-written `"wide"` entities, and
`tests/test_route_layout_contract.lua:146-155` feeds it a rotated block member. `tests/test_route_footprints.lua`
does check overlap on routed output, through `assert_no_overlap`, but only on three small hand-built
fixtures whose neighbouring tiles happen to be empty, so a half-tile shift hides there. That gap is this
lane.

The box rule already exists and this lane reuses it rather than writing a third copy —
`tests/test_route_footprints.lua:20-38`:

```lua
local function physical_box(entity)
    local name = tostring(entity.name or "")
    local direction = entity.direction or entity.dir or Grid.NORTH
    local splitter = name:find("splitter", 1, true) ~= nil
    local horizontal = direction == Grid.NORTH or direction == Grid.SOUTH
    ...
end
```

Trap: not every published entity carries `position`. Block members carry `x`, `y`, `w`, `h`.
`logic/bp/geometry.lua:70-79` is the rule — position first, then `x + w/2`. Indexing `entity.position.x`
blind crashes.

Trap: `Grid.NORTH` is `0`, `EAST` is `4`, `SOUTH` is `8`, `WEST` is `12`. A splitter facing north or south
spans **east to west**, and one facing east or west spans **north to south**. Getting that backwards makes a
guard that passes on the very defect it was cut for.

Trap: `tests/harness.lua`'s `H.shapes()` yields two shapes, so every `H.test` inside that loop counts twice
per interpreter. Both `lua5.2` and `lua5.4` must be green.

PRESERVE: `logic/**`, `tools/**`, `tests/harness.lua`, `tests/test_route_footprints.lua`,
`tests/test_route.lua`, `tests/test_route_chain.lua`, `tests/test_validate.lua`,
`tests/test_blueprint_physical_contract.lua`, `tests/golden/cases/player-red-science-1s/`,
`docs/round-16-census-baseline.json`, `docs/round-16-red-list.txt`, `docs/feature-contracts.md`,
`info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `tests/test_route_collision.lua` (new).

## What to build

**S1. `tests/test_route_collision.lua`.** Drive `Route` — never the validator, never the search — and assert
that **no two published entities overlap**. Four cases at least:

- **RX1** the frozen candidate `tests/fixtures/routing/player_chain_first_candidate.lua` routes and publishes
  zero overlapping pairs. Report the counts it measured: entities, belts, undergrounds, splitters.
- **RX2** a fixture that genuinely **builds a splitter**, with a belt already standing on the tile the
  splitter's second half would reach past. `branch_input()` in `tests/test_route_footprints.lua:60-83` is the
  right shape to start from; add the neighbouring belt that makes a half-tile shift collide. This case is the
  reason the lane exists, so it must fail when the shift is put back.
- **RX3** every published `splitter` is centred on its own two tiles: on the span axis its centre is a
  half-integer and on the other axis an integer, and the two tiles it covers are the anchor and exactly one
  orthogonal neighbour.
- **RX4** every published underground endpoint occupies exactly one tile, and no endpoint overlaps its own
  partner.

**S2. Prove the guard red before trusting it.** In a throwaway `git worktree`, put the defect back with

```sh
sed -i 's|entity_position(cell.x + side_x / 2, cell.y + side_y / 2)|entity_position(cell.x + 0.5 + side_x / 2, cell.y + side_y / 2)|' logic/bp/route.lua
```

and show `tests/test_route_collision.lua` goes **red**. A guard that passes both ways is not a guard. The
`red-proof` check below is exactly this and it is the check that matters most in this lane.

**S3. Say what it measured.** Each case prints the counts it saw, so the next round reads the geometry from
the test output instead of rebuilding a probe.

This lane changes **no** production file. It adds one test file and nothing else.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; lua5.2 tests/test_route_collision.lua >/dev/null 2>&1 || rc=1; sed -i 's|entity_position(cell.x + side_x / 2, cell.y + side_y / 2)|entity_position(cell.x + 0.5 + side_x / 2, cell.y + side_y / 2)|' $S/logic/bp/route.lua || rc=1; grep -q 'cell.x + 0.5 + side_x / 2' $S/logic/bp/route.lua || rc=1; (cd $S && lua5.2 tests/test_route_collision.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "collision-cases", "command": "sh tools/lane_rows.sh tests/test_route_collision.lua --min-cases 8", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "collision-green", "command": "for l in lua5.2 lua5.4; do $l tests/test_route_collision.lua 2>&1 | tail -1 | grep -q '0 failed' || exit 1; done; echo collision-green", "expect_exit": 0, "expect_regex": "collision-green", "timeout_s": 900}
{"name": "counts-reported", "command": "lua5.2 tests/test_route_collision.lua 2>&1 | grep -Eq 'splitter|entities' && echo counts-reported || { echo 'the cases must print the geometry they measured'; exit 1; }", "expect_exit": 0, "expect_regex": "counts-reported", "timeout_s": 900}
{"name": "adds-one-file", "command": "git diff --name-only round-16-wave3 HEAD | grep -v '^docs/tasks/146' | grep -v '^tests/test_route_collision.lua' | head -5 | ( ! grep . ) && echo adds-one-file || { echo 'this lane touched a file it does not own'; exit 1; }", "expect_exit": 0, "expect_regex": "adds-one-file", "timeout_s": 120}
{"name": "route-family-whole", "command": "for l in lua5.2 lua5.4; do $l tests/test_route.lua 2>&1 | tail -1 | grep -q '38 passed, 0 failed' || exit 1; $l tests/test_route_footprints.lua 2>&1 | tail -1 | grep -q '6 passed, 0 failed' || exit 1; $l tests/test_route_chain.lua 2>&1 | tail -1 | grep -q '4 passed, 0 failed' || exit 1; done; echo route-family-whole", "expect_exit": 0, "expect_regex": "route-family-whole", "timeout_s": 1800}
{"name": "oracle-whole", "command": "for l in lua5.2 lua5.4; do $l tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' || exit 1; done; echo oracle-whole", "expect_exit": 0, "expect_regex": "oracle-whole", "timeout_s": 900}
{"name": "no-new-red", "command": "sh tools/red_list.sh docs/round-16-red-list.txt", "expect_exit": 0, "expect_regex": "RED-LIST ok", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-16-wave3 --manifest docs/tasks/146.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
