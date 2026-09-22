# 150 guard: the validator has NEVER been tested against a splitter

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-150`, branch
`lane/150`, base tag `round-17-base` (resolve with `git rev-parse round-17-base`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Measured 2026-09-22 on this host:

```
grep -c splitter tests/test_validate.lua                      -> 0
grep -c splitter tests/test_blueprint_physical_contract.lua   -> 0
grep -c splitter tests/test_transport_handshake.lua           -> 0
```

**Zero.** The validator's three main test files never mention a splitter. Six test files drive both
`logic.bp.route` and `logic.bp.validate`, and not one of them puts a splitter in front of the validator's
walk.

That gap cost a whole round. The router was taught to walk out of a splitter's **second** tile on
2026-09-22 (`logic/bp/route.lua:1214-1227`, with a comment recording the measurement), and
`logic/bp/validate.lua` was never mirrored. On the player's real sheet that produced `20`
`BP_V_ROUTE_DISCONTINUOUS` and `257` cascading `BP_V_TRANSPORT_UNUSED` on the very first candidate, and
`ok=false`, so **no blueprint was ever delivered**.

Two defects are being fixed in the spine this session, both in `logic/bp/validate.lua`:

1. **`:589-604`** — the splitter side-neighbour was a dead branch. It added the tile at
   `rotate_dir(direction, Grid.EAST)` from `transport_tile(info)`, which is the splitter's **own** second
   tile, registered under the **same** `info` by `transport_cells`, and then rejected by `add_at`'s
   `next_info ~= info` guard. A splitter has an output in front of **each** of its two tiles.
2. **`:513-520`** — `entity_tile_rect` never rotated `w`/`h` by direction. The splitter spec carries the
   NORTH footprint (`tile_w = 2, tile_h = 1`, `logic/catalog.lua:8`) and router splitters publish no
   `entity.w`/`entity.h`, so an EAST or WEST splitter registered on the wrong two tiles: a real hole in
   `transport_by_cell` plus a phantom occupancy elsewhere.

**This lane is the guard that should have existed.**

## Traps, each measured

**Trap: a splitter's two tiles and its position.** A tile centre is at `(n + 0.5, m + 0.5)`. A two-tile
splitter sits at the midpoint of its two tile centres, so exactly one of its coordinates is a whole number.
Measured from the player's sheet, 2026-09-22: `r:343` at `pos=(17.5, 41)` facing `WEST` covers tiles
`(17,40)` and `(17,41)`; `r:289` at `pos=(12.0, 11.5)` facing `NORTH` covers `(11,11)` and `(12,11)`. Get
this backwards and the guard passes on the very defect it was cut for.

**Trap: `Grid.NORTH` is `0`, `EAST` is `4`, `SOUTH` is `8`, `WEST` is `12`.** A splitter facing north or
south spans **east to west**; one facing east or west spans **north to south**.

**Trap: the validator refuses on ANY record.** `state.ok` is a pure emptiness test on `work.errors`
(`logic/bp/validate.lua:2117-2124`) — no severity split. So a fixture that is accepted must be clean of
`BP_V_TRANSPORT_UNUSED` too, which means **every** entity it carries has to serve a real obligation. Copy the
shape of the working control at `tests/test_blueprint_physical_contract.lua:104-155`: a plan with a real
step, real ports, real segments and real bindings. Its two hands declare their `flow_id`, and an undeclared
hand fails closed on purpose.

**Trap: assert the CODE, never only `ok == false`.** A row written loosely passes on an unrelated complaint.
`tests/test_blueprint_physical_contract.lua:259-265` has the `rejects` helper that asserts the code and that
the record names the entity at fault; reuse that shape rather than writing a third copy.

**Trap: `tests/harness.lua`'s `H.shapes()` yields two shapes**, so every `H.test` inside that loop counts
twice per interpreter. Both `lua5.2` and `lua5.4` must be green.

PRESERVE: `logic/**`, `tools/**`, `tests/harness.lua`, `tests/test_validate.lua`,
`tests/test_blueprint_physical_contract.lua`, `tests/test_transport_handshake.lua`,
`tests/test_route_layout_contract.lua`, `tests/test_route_chain.lua`, `docs/round-16-census-baseline.json`,
`docs/round-16-red-list.txt`, `docs/feature-contracts.md`, `info.json`, `mod-description.md`,
`.agent-lane.toml`.

Files this lane owns: `tests/test_validate_splitter.lua` (new).

**This lane changes NO production file.** It adds one test file and nothing else. If a row cannot be made
green without a production change, say so in the lane report and leave the row failing with a comment naming
the line — never edit `logic/`.

## What to build

**`tests/test_validate_splitter.lua`.** Hand-built candidates the **validator** judges, each carrying a real
splitter. At minimum:

- **VS1** a belt run enters a splitter and leaves by the **anchor** tile's output. Accepted, `state.ok` true.
- **VS2** the same run leaves by the splitter's **second** tile's output. Accepted. **This is the row that is
  red before the spine fix and green after it.**
- **VS3** an **EAST or WEST** facing splitter, whose footprint is the one `entity_tile_rect` mis-registered.
  Its two covered tiles are exactly the two the position implies, and a run through it is accepted.
- **VS4** a **NORTH or SOUTH** facing splitter, which registered correctly even before the fix, so VS3 and
  VS4 together isolate the rotation defect from the second-output defect.
- **VS5** a splitter carrying **two** flows. `multi_flow_hands` is ON in production since 2026-09-22
  (`logic/bp/flags.lua`), a belt may carry at most two flows, and each flow must be witnessed separately.
- **VS6** a negative control: a run that genuinely does not continue out of the splitter is **rejected**, and
  rejected as `BP_V_ROUTE_DISCONTINUOUS`, named. Without this the file proves nothing.

**THE GUARD IS RED AT THIS LANE'S BASE, AND THAT IS CORRECT.** `round-17-base` still carries both defects.
`VS2` and `VS3` **must fail** here. They go green when the spine's fix merges. A guard that is green before
the fix is proving nothing. Do **not** weaken a row to make it pass, and do **not** edit `logic/`.

State plainly in the lane report which rows are red at base and which are green, with the exact failure text
of each red row. That list is the lane's deliverable as much as the file is.

**Say what it measured.** Each row prints the splitter's position, its facing, and the two tiles it covers,
so the next round reads the geometry from test output instead of rebuilding a probe.

## What done mean

Two checks. A check block takes one `gateslot` lease PER check and hands it back between them, so nine cheap
checks means nine trips to the back of a shared queue. Everything cheap is folded in with `&&`.

`VS1`, `VS4` and `VS6` must be GREEN at base: they do not depend on either defect. `VS2` and `VS3` must be
RED at base: they are the defects. `VS5` may be either, and the report says which.

```checks
{"name": "splitter-guard", "command": "git diff --name-only round-17-base HEAD | grep -v '^docs/tasks/150' | grep -v '^tests/test_validate_splitter\\.lua$' | ( ! grep . ) && sh tools/lane_rows.sh tests/test_validate_splitter.lua --min-cases 6 && for l in lua5.2 lua5.4; do $l tests/test_validate.lua 2>&1 | tail -1 | grep -q '44 passed, 0 failed' || exit 1; $l tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' || exit 1; done; lua5.2 tests/test_validate_splitter.lua 2>&1 | grep -Eq 'covers|tiles' || exit 1; echo splitter-guard-ok", "expect_exit": 0, "expect_regex": "splitter-guard-ok", "timeout_s": 1200}
{"name": "red-at-base-green-rows-pass", "command": "out=$(lua5.2 tests/test_validate_splitter.lua 2>&1); echo \"$out\" | grep -q 'VS1' && echo \"$out\" | grep -q 'VS6' || exit 1; for row in VS1 VS4 VS6; do echo \"$out\" | grep \"^FAIL\" | grep -q \"$row\" && { echo \"$row must be GREEN at base and is red\"; exit 1; }; done; echo \"$out\" | grep '^FAIL' | grep -q 'VS2' || { echo 'VS2 must be RED at base; it is the defect this lane exists for'; exit 1; }; echo red-at-base-ok", "expect_exit": 0, "expect_regex": "red-at-base-ok", "timeout_s": 900}
```

# bound: 4000s
