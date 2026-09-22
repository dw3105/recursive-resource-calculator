# 158 waste: no U-turn that buys nothing, no dive that was never needed

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-158`, branch
`lane/158`, base tag `round-19-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Round 18's delivery carries shapes the player would never build, and **nothing in the tree catches either**.
Measured from the delivered bytes 2026-09-22, `~/share/RRC/player-red-science-1s-20260922.txt`:

```
                     ours   player's own factory
one-tile U-turns        3                      0 wasteful
underground pairs       7                      0
  of span 2             5                      -
```

**A U-turn costs 2 belts and buys nothing.** The run goes out, drops one tile, and comes straight back:

```
(1.5,27.5) W  ->  (0.5,27.5) S  ->  (0.5,28.5) E  ->  back east
net movement: ONE tile south.  price: TWO extra belts at x = 0.5.
```

**A hairpin that goes somewhere is legal and must stay legal.** The player's own working factory has one,
four chains long, at `(203.5,1076.5) N -> (205.5,1075.5) S`. **The row must pass on theirs and fail on
ours.** The difference is that ours returns to within one tile of its own start.

**A span-2 underground is two entities to skip ONE tile.** `crossing_target`
(`logic/bp/route.lua:1725-1750`) dives the moment the very next tile is blocked and never asks whether the
tile was worth diving under.

Nothing guards either shape. The only thing close is `tests/test_route_chain.lua` RC2's three `<=` ceilings
on one frozen candidate, and **this session raised its underground ceiling from 6 to 8 to accept exactly
the dive the player then complained about. That was the wrong call and this lane reverts it.**

`grep -rni "simplify\|straighten\|smooth\|cleanup\|prune" logic/bp/route.lua` returns **nothing**: no pass
ever rewrites a laid route.

Measured baselines, green, none may regress:

```
lua5.2 tests/test_route_chain.lua        14 cases, 14 passed, 0 failed
lua5.2 tests/test_route_collision.lua     8 cases,  8 passed, 0 failed
lua5.2 tests/test_route_footprints.lua    6 cases,  6 passed, 0 failed
```

## Traps, each measured

**Trap: judge the DELIVERED BYTES or a routed result, never the router's own bookkeeping.** A guard that
reads `work.segments_by_cell` proves nothing about what ships.

**Trap: `work.entity_by_segment` maps `segment_id` to an ENTITY, never a segment**
(`logic/bp/route.lua:1164`). Lane 152 was refused for reading it as a segment and scoring 10 of 12 on the
tree carrying the defect it existed to catch. Use `work.segments_by_cell`, or read the published entities.

**Trap: a staircase is FREE and must stay legal.** Moving one tile diagonally needs two turns; that is not
waste. Only a chain that comes back to within one tile of its own start is.

**Trap: an underground is sometimes right.** A run that meets a belt of a FOREIGN flow head-on has exactly
one legal answer, because a splitter never turns and flows may not merge. The row must fail only on a dive
whose covered tiles were free, or whose span is below 2.

**Trap: `Grid.NORTH` is `0`, `EAST` `4`, `SOUTH` `8`, `WEST` `12`**, opposite is `(d + 8) % 16`.

**Trap: `tests/harness.lua`'s `H.shapes()` yields two shapes.** Both interpreters must be green.

PRESERVE: `logic/**`, `tools/**`, `tests/harness.lua`, every other file under `tests/` except the two named
below, `docs/**`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

## Files this lane owns

`tests/test_route_waste.lua` (new) and `tests/test_route_chain.lua` (RC2 and RC8's underground ceiling
only). **This lane changes NO production file.** If a row cannot go green without one, say so in the lane
report and leave it failing with a comment naming the line.

## What to build

1. **`tests/test_route_waste.lua`**:
   - **RW0** the fixture laid at least one run, so no row below is vacuous.
   - **RW1** no U-turn that buys nothing: no belt chain returns to within one tile of its own start.
   - **RW2** a hairpin that goes somewhere passes: build the player's shape,
     `(203.5,1076.5) N -> (205.5,1075.5) S`, and assert RW1's own helper accepts it.
   - **RW3** no underground whose covered tiles were free when it was laid.
   - **RW4** no underground of span below 2.
   - **RW5** a negative control the file can fail on.
2. **Restore `tests/test_route_chain.lua`'s underground ceiling to 6**, in RC2 and RC8, with a comment
   saying the 6-to-8 raise was made on 2026-09-22 to accept a dive the player then rejected in game.
   **If the fixture genuinely needs 8 after the spine's work, report that number and leave the row red** —
   do not raise the ceiling a second time to make it pass.

**Each row prints the tiles it judged**, so the next round reads geometry from test output.

**RED AT `round-19-base`**, where the delivery carries 3 U-turns and 7 dives. Say which rows are red there.

## What done mean

```checks
{"name": "route-waste", "command": "git diff --name-only round-19-base HEAD | grep -v '^docs/tasks/158' | grep -Ev '^(tests/test_route_waste\\.lua|tests/test_route_chain\\.lua)$' | ( ! grep . ) && sh tools/lane_rows.sh tests/test_route_waste.lua --min-cases 6 && for l in lua5.2 lua5.4; do $l tests/test_route_collision.lua 2>&1 | tail -1 | grep -q '8 passed, 0 failed' || exit 1; $l tests/test_route_footprints.lua 2>&1 | tail -1 | grep -q '6 passed, 0 failed' || exit 1; $l tests/test_route_splitter_physics.lua 2>&1 | tail -1 | grep -q '12 passed, 0 failed' || exit 1; done && grep -q 'underground endpoints stay at or below the measured 6' tests/test_route_chain.lua && echo route-waste-ok", "expect_exit": 0, "expect_regex": "route-waste-ok", "timeout_s": 1800}
{"name": "red-at-base", "command": "set -e; base=$(mktemp -d); git worktree add -q --detach \"$base\" round-19-base; cp tests/test_route_waste.lua \"$base/tests/test_route_waste.lua\"; cd \"$base\"; out=$(lua5.2 tests/test_route_waste.lua 2>&1 || true); cd - >/dev/null; git worktree remove --force \"$base\"; echo \"$out\" | grep '^FAIL' | grep -Eq 'RW1|RW3|RW4' || { echo 'no waste row is RED at round-19-base, where the delivery carries 3 U-turns and 7 dives; the file proves nothing'; exit 1; }; echo \"$out\" | grep '^FAIL' | grep -q 'RW2' && { echo 'RW2 must be GREEN: a hairpin that goes somewhere is legal'; exit 1; }; echo red-at-base-ok", "expect_exit": 0, "expect_regex": "red-at-base-ok", "timeout_s": 1200}
```

Re-cut because: none

# bound: 4000s

Reviewer ask: does RW1 accept the player's own four-chain hairpin while refusing our two-tile U-turn, and
was RC2's ceiling restored to 6 rather than raised again?
