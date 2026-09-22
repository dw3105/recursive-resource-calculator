# 155 guard re-cut: a published splitter never turns flow, and the row must tell dir=12 from dir=0

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-155`, branch
`lane/155`, base tag `round-18-guard-base` (resolve with `git rev-parse round-18-guard-base`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## Re-cut because

Lane 152 delivered `tests/test_route_splitter_physics.lua`, 111 lines, 6 rows, 12 cases. **It was refused
on measurement**, 2026-09-22 on this host: 10 of 12 passed at the tree carrying the very defect the file
exists to catch. Four defects, each verified:

1. **`work.entity_by_segment` maps `segment_id` to an ENTITY, never to a segment.**
   `logic/bp/route.lua:1164` reads `work.entity_by_segment[segment.segment_id] = first`. So in
   `local segment = state.work.entity_by_segment[e.segment_id]`, `segment` IS the published entity, and
   `H.equal(e.direction or e.dir, segment.direction, ...)` in **SP1** compares the entity's direction with
   **itself**. Trivially true. **SP3** repeats the same comparison and is trivially true for the same
   reason.
2. **SP4 reads `segment.length` on that entity**, which is `nil`, so `nil > 1` raises and SP4 is the only
   row that fails -- for the wrong reason.
3. **SP6 asserts `#splitters >= 0`**, which no tree can ever fail.
4. **SP2's two branches build the same tile pair.** The `else` branch, for an EAST or WEST splitter, still
   computes `{floor(p.x), floor(p.y - 0.5)}` and `{floor(p.x), floor(p.y + 0.5)}` -- a NORTH/SOUTH
   footprint. The rotation it exists to isolate is never tested. It also ends on
   `H.equal(#tiles, 2, ...)`, which a two-element literal cannot fail.

There is also a Lua precedence bug in the unused `geometry` helper:
`d == Grid.NORTH or d == Grid.SOUTH and {x + 1, y} or {x, y + 1}` returns `true` for NORTH, never a table.

**The fixture itself is good and must be kept.** Measured on this host 2026-09-22, the same fixture, same
ops, run in both trees:

```
round-18-base (the defect):   done=true ok=true   SPL r:7 pos=(6.5,2) dir=12   splitters=1
round-18-guard-base (fixed):  done=true ok=true   SPL r:7 pos=(6,2.5) dir=0    splitters=1
```

**One splitter either way. `dir=12` WEST against `dir=0` NORTH, and `(6.5,2)` against `(6,2.5)`.** A row
that cannot tell those two apart is not a guard.

## What is true

**A splitter never turns flow.** Two tiles side by side ACROSS its own direction, items in at the back of
both, out at the front of both. **No side output.** `logic/bp/route.lua` used to orient a splitter to the
NEW demand, severing the trunk feeding it; the spine fixed that, and this file is the guard that should
have existed.

`tests/test_route_footprints.lua`, `tests/test_route_collision.lua` and `tests/test_route_network.lua` all
judge a splitter's BOX -- that it covers two orthogonal tiles and overlaps nothing. **Not one of them asks
which way it faces relative to the belt it was built on.**

## Traps, each measured

**Trap: `work.entity_by_segment` is `segment_id -> entity`.** To reach the SEGMENT, use
`state.work.segments_by_cell[coordinate_key(x, y)]`, or scan `state.result.segments`. A segment carries
`direction`, `splitter_direction`, `splitter_anchor_x`, `splitter_anchor_y`, `splitter_second_key` and
`length`; the entity carries `position`, `direction`, `dir` and `splitter`. **Print both in the failure
message so the next reader never has to re-derive which is which.**

**Trap: judge the PUBLISHED entity, and cross-check it against the segment.** The blueprint carries
`entity.position` and `entity.direction`. A row that reads only router bookkeeping proves nothing about the
bytes; a row that reads only the entity cannot know what the trunk was doing.

**Trap: a splitter's two tiles and its position.** A tile centre is at `(n + 0.5, m + 0.5)`. A two-tile
splitter sits at the midpoint of its two tile centres, so **exactly one of its coordinates is a whole
number**. `dir=0` NORTH or `dir=8` SOUTH spans EAST-WEST, so `x` is whole and `y` ends in `.5`;
`dir=4` EAST or `dir=12` WEST spans NORTH-SOUTH, so `y` is whole and `x` ends in `.5`. Verified above:
`(6,2.5) dir=0` and `(6.5,2) dir=12`. **The two branches must compute DIFFERENT tile pairs.**

**Trap: `Grid.NORTH` is `0`, `EAST` is `4`, `SOUTH` is `8`, `WEST` is `12`** (`logic/bp/grid.lua:198-220`).

**Trap: Lua `and`/`or` binds tighter than you expect.** `a or b and c or d` is `a or ((b and c) or d)`.
Parenthesise, or use an `if`.

**Trap: a row that quantifies over an empty list passes vacuously.** Every row here must **assert the
fixture published at least one splitter** before quantifying, so a future change that silently drops the
splitter turns the file red rather than green.

**Trap: `tests/harness.lua`'s `H.shapes()` yields two shapes**, so every `H.test` inside that loop counts
twice per interpreter. Both `lua5.2` and `lua5.4` must be green.

PRESERVE: `logic/**`, `tools/**`, `tests/harness.lua`, and every other file under `tests/`,
`docs/round-16-census-baseline.json`, `docs/round-16-red-list.txt`, `docs/feature-contracts.md`,
`info.json`, `mod-description.md`, `.agent-lane.toml`.

## Files this lane owns

`tests/test_route_splitter_physics.lua`. **Nothing else.** This lane changes NO production file.

## What to build

Rewrite `tests/test_route_splitter_physics.lua`, keeping lane 152's fixture. Rows, each of which must fail
at `round-18-base` and pass here:

- **SP0** the fixture published at least one splitter, so no row below is vacuous
- **SP1** every published splitter's `entity.direction` equals the `direction` of the trunk SEGMENT it was
  built on, read from `segments_by_cell`, never from `entity_by_segment`
- **SP2** the footprint follows the facing: NORTH/SOUTH gives whole `x` and half `y` and spans EAST-WEST;
  EAST/WEST gives half `x` and whole `y` and spans NORTH-SOUTH. **The two branches compute different tiles.**
- **SP3** no belt feeds a splitter from its SIDE. A feeding belt enters the back of a covered tile, so its
  heading equals the splitter's direction
- **SP4** the trunk the splitter was built on still reaches past it: the segment's own chain continues

Keep a negative control that the file can fail on, and make it a hand-built turning splitter judged by the
SAME helper the real rows use -- lane 152's control re-implemented the comparison inline, so it proved the
control and nothing about the rows.

**Each row prints the splitter's position, its facing, the two tiles it covers, the trunk segment's
direction, and the feeding belt's heading.**

## What done mean

Two checks. A check block takes one `gateslot` lease PER check and hands it back between them.

```checks
{"name": "splitter-physics", "command": "git diff --name-only round-18-guard-base HEAD | grep -v '^docs/tasks/155' | grep -v '^tests/test_route_splitter_physics\\.lua$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_route_splitter_physics.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; $l tests/test_route_collision.lua 2>&1 | tail -1 | grep -q '8 passed, 0 failed' || exit 1; $l tests/test_route_footprints.lua 2>&1 | tail -1 | grep -q '6 passed, 0 failed' || exit 1; $l tests/test_validate_splitter.lua 2>&1 | tail -1 | grep -q '12 passed, 0 failed' || exit 1; done && lua5.2 tests/test_route_splitter_physics.lua 2>&1 | grep -Eq 'covers|facing' && echo splitter-physics-ok", "expect_exit": 0, "expect_regex": "splitter-physics-ok", "timeout_s": 1800}
{"name": "red-at-the-defect", "command": "set -e; base=$(mktemp -d); git worktree add -q --detach \"$base\" round-18-base; cp tests/test_route_splitter_physics.lua \"$base/tests/test_route_splitter_physics.lua\"; cd \"$base\"; out=$(lua5.2 tests/test_route_splitter_physics.lua 2>&1 || true); cd - >/dev/null; git worktree remove --force \"$base\"; for row in SP1 SP2 SP3; do echo \"$out\" | grep '^FAIL' | grep -q \"$row\" || { echo \"$row is GREEN at round-18-base, where the splitter is published dir=12 at (6.5,2); it proves nothing\"; exit 1; }; done; echo \"$out\" | grep '^FAIL' | grep -q 'SP0' && { echo 'SP0 must be GREEN at round-18-base; the fixture publishes one splitter there too'; exit 1; }; echo red-at-the-defect-ok", "expect_exit": 0, "expect_regex": "red-at-the-defect-ok", "timeout_s": 1200}
```

# bound: 4000s

Reviewer ask: does every row fail at `round-18-base`, where the same fixture publishes one splitter at
`(6.5,2)` facing `dir=12`, and does any row read `work.entity_by_segment` as though it were a segment?
