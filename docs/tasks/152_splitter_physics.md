# 152 physics: a published splitter never turns flow

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-152`, branch
`lane/152`, base tag `round-18-base` (resolve with `git rev-parse round-18-base`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**A splitter never turns items.** A real Factorio splitter covers two tiles side by side across its own
direction. Items enter at the **back** of both tiles and leave at the **front** of both tiles. **There is no
side output. Ever.**

`logic/bp/route.lua` builds one that turns. When a new demand crosses an existing trunk at a different
heading, `logic/bp/route.lua:1350` reads `local splitter_direction = direction` — the **new demand's**
direction, never the trunk's `segment.direction`. A north trunk crossed by a west demand becomes a
**WEST-facing** splitter, whose input side then faces east, so the trunk feeding it from the south is
severed.

Measured on the player's sheet 2026-09-22, this host: `r:279` covers `(12,19)`+`(12,20)` facing `WEST` while
the copper trunk runs north through `(12,21)`. The validator's walk reaches **23 tiles of a 67-entity
network**:

```
7:24,8:24,9:24,10:24,11:24,12:24,12:23,12:22,12:21,12:19,
11:20,10:20,9:20,8:20,7:20,6:20,5:20,4:20,3:20,3:19,3:18,3:17,4:17
```

`12:21 -> 12:19` (the splitter) `-> 11:20`, and **`12:18` is never reached.** The north trunk is orphaned.
The validator is right. The router is wrong.

**Nothing in the tree asserts this.** `tests/test_route_footprints.lua`, `tests/test_route_collision.lua`
and `tests/test_route_network.lua` all judge a splitter's **box** — that it covers two orthogonal tiles and
overlaps nothing. **Not one of them asks which way it faces relative to the belt it was built on.** The
router shipped turning splitters for rounds and no test noticed.

`tests/test_validate_splitter.lua` (12 of 12 green, both interpreters) guards the **validator** reading a
splitter. This lane guards the **router** publishing one. They are different halves and both are needed.

## Traps, each measured

**Trap: a splitter's two tiles and its position.** A tile centre is at `(n + 0.5, m + 0.5)`. A two-tile
splitter sits at the midpoint of its two tile centres, so exactly one of its coordinates is a whole number.
Measured from the player's sheet 2026-09-22: `r:343` at `pos=(17.5, 41)` facing `WEST` covers `(17,40)` and
`(17,41)`; `r:289` at `pos=(12.0, 11.5)` facing `NORTH` covers `(11,11)` and `(12,11)`.

**Trap: `Grid.NORTH` is `0`, `EAST` is `4`, `SOUTH` is `8`, `WEST` is `12`** (`logic/bp/grid.lua:198-220`).
A splitter facing north or south spans **east to west**; one facing east or west spans **north to south**.
`Grid.rotate_dir(a, b)` is `(a + b) % 16`.

**Trap: the router records TWO contradictory headings on a converted segment.** `logic/bp/route.lua:1371`
sets `segment.splitter_direction`, and `segment.direction` is **never updated**, so it still carries the
trunk's heading from `logic/bp/route.lua:1380`. **That pair is the measurement this lane exists for:**
a physically real splitter has `segment.splitter_direction == segment.direction`. Today's router does not.

**Trap: judge the PUBLISHED entity, never only the segment.** The blueprint carries
`entity.direction`/`entity.dir` (`logic/bp/route.lua:1368-1369`) and `entity.position`
(`logic/bp/route.lua:1365`). A guard that reads only `work.segments_by_cell` proves nothing about the bytes.
Read the routed result's entities, the way `tests/test_route_collision.lua` already does.

**Trap: the spine is rewriting `logic/bp/route.lua` in parallel, right now.** Do **not** edit it, do not
read its future shape, and do not write a row that only passes against a fix you guessed. Write what the
GAME requires and let the row be red until the fix lands.

**Trap: assert the geometry, never only `ok == false`.** A row written loosely passes on an unrelated
complaint. Name the splitter, its position, its facing, the two tiles it covers, and the heading of the belt
feeding it.

**Trap: `tests/harness.lua`'s `H.shapes()` yields two shapes**, so every `H.test` inside that loop counts
twice per interpreter. Both `lua5.2` and `lua5.4` must be green on the rows that are meant to be green.

**Trap: a fixture already exists.** `tests/fixtures/routing/player_chain_first_candidate.lua` is the frozen
first candidate of the player's own sheet and is what `tests/test_route_chain.lua` drives. Reuse it or a
small routed fixture of the same shape; **do not** run the full generator, which costs 324 s for the sheet.

PRESERVE: `logic/**`, `tools/**`, `tests/harness.lua`, `tests/test_route.lua`,
`tests/test_route_chain.lua`, `tests/test_route_collision.lua`, `tests/test_route_footprints.lua`,
`tests/test_route_network.lua`, `tests/test_validate.lua`, `tests/test_validate_splitter.lua`,
`tests/test_blueprint_physical_contract.lua`, `tests/test_census_codes_live.lua`,
`tests/fixtures/**`, `docs/round-16-census-baseline.json`, `docs/round-16-red-list.txt`,
`docs/feature-contracts.md`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

## Files this lane owns

`tests/test_route_splitter_physics.lua` (new).

**This lane changes NO production file and NO existing test file.** If a row cannot be made green without a
production change, say so in the lane report and leave the row failing with a comment naming the line —
never edit `logic/`.

## What to build

**`tests/test_route_splitter_physics.lua`.** Route a fixture, then judge **every** published splitter:

- **SP1 — facing.** A splitter's `entity.direction` equals the `direction` of the trunk segment it was built
  on. **This is the row that is red at base**; it is the defect.
- **SP2 — footprint.** A splitter covers exactly two tiles, side by side **across** its own direction:
  north/south spans east-west, east/west spans north-south. Derived from `entity.position`, never from the
  router's bookkeeping.
- **SP3 — input side.** Every belt feeding a splitter enters through the **back** of a covered tile.
  **No belt feeds a splitter from its side.** Red at base for the same reason as SP1.
- **SP4 — the trunk survives.** A trunk that continued past the cell before conversion is still reachable
  from the splitter's input side after it. This is contract 28.7 stated as physics.
- **SP5 — negative control.** A hand-built splitter that genuinely does turn flow is **named**, so the file
  proves it can fail. Without this the file proves nothing.
- **SP6 — no splitter at all is legal.** Contract 28.8 prefers a continuation and the player's own factory
  has **zero** splitters, so a fixture that publishes none passes every row above vacuously and says so.

**THE GUARD IS RED AT THIS LANE'S BASE, AND THAT IS CORRECT.** `round-18-base` still builds turning
splitters. **SP1 and SP3 must fail here.** They go green when the spine's fix merges. A guard that is green
before the fix is proving nothing. Do **not** weaken a row to make it pass.

**Say what it measured.** Each row prints the splitter's position, its facing, the two tiles it covers, and
the heading of the belt feeding it, so the next round reads the geometry from test output instead of
rebuilding a probe.

State plainly in the lane report which rows are red at base and which are green, with the exact failure text
of each red row.

## What done mean

Two checks. A check block takes one `gateslot` lease PER check and hands it back between them, so nine cheap
checks means nine trips to the back of a shared queue. Everything cheap is folded in with `&&`.

```checks
{"name": "splitter-physics", "command": "git diff --name-only round-18-base HEAD | grep -v '^docs/tasks/152' | grep -v '^tests/test_route_splitter_physics\\.lua$' | ( ! grep . ) && sh tools/lane_rows.sh tests/test_route_splitter_physics.lua --min-cases 6 && for l in lua5.2 lua5.4; do $l tests/test_route_collision.lua 2>&1 | tail -1 | grep -q '8 passed, 0 failed' || exit 1; $l tests/test_route_footprints.lua 2>&1 | tail -1 | grep -q '6 passed, 0 failed' || exit 1; $l tests/test_validate_splitter.lua 2>&1 | tail -1 | grep -q '12 passed, 0 failed' || exit 1; done && lua5.2 tests/test_route_splitter_physics.lua 2>&1 | grep -Eq 'covers|facing|tiles' && echo splitter-physics-ok", "expect_exit": 0, "expect_regex": "splitter-physics-ok", "timeout_s": 1800}
{"name": "red-at-base", "command": "out=$(lua5.2 tests/test_route_splitter_physics.lua 2>&1); for row in SP2 SP5 SP6; do echo \"$out\" | grep '^FAIL' | grep -q \"$row\" && { echo \"$row must be GREEN at base and is red\"; exit 1; }; done; echo \"$out\" | grep '^FAIL' | grep -q 'SP1' || { echo 'SP1 must be RED at base; it is the defect this lane exists for'; exit 1; }; echo \"$out\" | grep '^FAIL' | grep -q 'SP3' || { echo 'SP3 must be RED at base; a splitter has no side input'; exit 1; }; echo red-at-base-ok", "expect_exit": 0, "expect_regex": "red-at-base-ok", "timeout_s": 1200}
```

Re-cut because: none

# bound: 4000s

Reviewer ask: does this file fail at `round-18-base` for the RIGHT reason — a splitter whose facing
disagrees with the trunk it was built on — rather than on box overlap, which three existing files already
cover?
