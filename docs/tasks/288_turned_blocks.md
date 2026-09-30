# 288_turned_blocks: a turned Block gets world port tiles, so slides, hops, seating and make-room work on it

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-288`, branch `lane/288`,
base tag `round-52-base` (`f13b7496e3df8592499363ee4c50bf28df08c0d2`), merge target `int/r52`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tests/golden/generate.lua`, `tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet
or headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4) or `timeout 90 python3 -m unittest tests/<file>.py`;
headless test files only offline: `timeout 90 lua5.2 tests/game/offline.lua tests/game/<file>.lua`. Never use
`coroutine` or `math.random`. `require` only at file top level. **No game item or entity name in `logic/`.** Every
new test must FAIL on the base code where this task says "red on base" (say so in its header comment, with date
2026-09-30); commit it red first, then the code.

## Explain very simply

Read `CONTEXT.md` section "Layout" (Block, Row, Turn, Drawn pack). A Block is placed with `dir` 0/4/8/12. Until
round 51 the packer placed normal Blocks only north (`groups.lua:1283` `allowed_dirs={NORTH}`) and Row Blocks
north/east (`:1519`). The Drawn pack (`RRC_PACK=sugiyama`, `pack.lua:1028-1039`) now places every Block any of 4
ways. Code after pack never learnt turned Blocks:

- `Groups.materialize` (`groups.lua:2806-2825`): only `dir == NORTH` ports get world `x`, `y`. Turned ports keep
  source-frame `attach_dx/attach_dy`, `_block_w/_block_h`; comment there: the validator's edge predicate reads
  attach data as one frame, "Supplying x/y here would ask the validator to rotate the already-placed block a
  second time". Route (`route.lua:476,507,569`) and validate (`validate.lua:819,1475-1487`) derive world tiles
  themselves when `port.x == nil`.
- `Hands.offer_slides` (`hands.lua:12-16,41`) and the hop pass (`:68`) need `port.x` -> no slide, no hop on turned
  Blocks (comment `hands.lua:15-16` says so).
- `Seat.run` (`seat.lua:25-26`) needs `port.hop_options` -> seating skipped on turned Blocks.
- `Hands.free_cell` (`hands.lua:211-260`) does `port.x - hand.x` (`:237`) -> nil arithmetic crash on a turned
  Block hand (Route.free_cell asks it when power makes room).
- `RunDir.choose` (`run_dir.lua:99-100,164-165`) uses unrotated `other.w/2`, `other.h/2`, `other.w/other.h` for
  partner centre and overlap -> wrong for Blocks at dir 4/12.

Measured 2026-09-30 (round 51 drawn verdict): turned sheets carry 18-21% more entities (am2 287->348, inserter-bulk
258->313, red-green 609->718). Layered (default) also places Row Blocks east (`turned=` up to 37 on blue), so they
lose slides/hops today too; fixing that may change default bytes - allowed when valid (player ruling 2026-09-30).

## What to build

1. `groups.lua` materialize: every turned placed port gets its world tile in PRIVATE fields
   `placed_port._world_x, placed_port._world_y` (= `geometry.x, geometry.y` from `Grid.place_port`, already
   computed there) and `placed_port._place_dir = dir`. Do NOT set `x`/`y` on turned ports (validator
   double-rotation trap above). North ports stay byte-identical.
2. One helper in `hands.lua`: `port_tile(port)` -> `port.x or port._world_x, port.y or port._world_y`. Use it in
   `offer_slides`, the hop pass and `free_cell` wherever they read `port.x/port.y`.
3. Moving a turned port (slide in `free_cell`, and every slide/hop apply path in `hands.lua` that writes
   `port.x, port.y = port.x + dx, ...`): update `_world_x/_world_y` by `(dx, dy)` AND the source-frame
   `attach_dx/attach_dy` by the world delta rotated back `Grid.rotate_vector(dx, dy, (16 - _place_dir) % 16)`,
   so route/validate, which derive the tile from attach data, see the moved tile. North ports keep today's
   `port.x` update only.
4. `seat.lua`: works once hops exist; fix any `port.x` read the same way.
5. `run_dir.lua:99-100,164-165`: use rotated size `Grid.rotate_size(other.w, other.h, <placement dir>)` for centre
   and overlap.
6. Tests `tests/test_turned_block.lua` (replace the stub; header: TB1-TB5 red on round-52-base):
   - TB1 materialize a 1-machine Block (hand-built like `tests/test_hands.lua` fixtures) at dir 4, 8, 12: every
     port has `_world_x/_world_y` == `Grid.place_port` tile; `x`/`y` stay nil; dir 0 output unchanged.
   - TB2 `Hands.offer_slides` offers slide options on the dir 4 Block (red on base: none).
   - TB3 `Hands.free_cell` on a dir 4 Block hand returns without error (red on base: nil arithmetic) and, when it
     slides, the tile `Grid.place_port` derives from the moved attach data equals `_world_x/_world_y`.
   - TB4 seat runs on a turned Block with hop options (no skip).
   - TB5 `RunDir.choose` overlap with a dir 4 partner of w=5,h=3 uses rotated 3x5.
   Print "TB1".."TB5" when each passes.
7. Keep green (one at a time): the test list in the first check below.

## Files this lane owns

logic/bp/groups.lua, logic/bp/hands.lua, logic/bp/seat.lua, logic/bp/run_dir.lua, tests/test_turned_block.lua, docs/tasks/288_turned_blocks.md. In `groups.lua` touch only `Groups.materialize` port placement (2700-2830).

## Commit, THEN check

Commit on `lane/288`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane288-tests", "command": "git diff --name-only round-52-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|logic/bp/hands\\.lua|logic/bp/seat\\.lua|logic/bp/run_dir\\.lua|tests/test_turned_block\\.lua|docs/tasks/288_turned_blocks\\.md)$' | ( ! grep . ) && for t in test_turned_block test_hands test_hands_hop test_hand_economy test_seat test_seat_hand_taken test_run_dir test_run_dir_obstacle test_groups test_groups_fluid_row test_groups_fluid_box_order test_orient test_pack_drawn test_search_draw_phase test_drawn_e2e test_route test_validate_transport_shapes test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane288-tests-ok", "expect_exit": 0, "expect_regex": "lane288-tests-ok", "timeout_s": 3000}
{"name": "lane288-fast", "command": "out=$( (timeout 120 lua5.2 tests/test_turned_block.lua) 2>&1); for c in TB1 TB2 TB3 TB4 TB5; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -Eq 'FAILED|[1-9][0-9]* failed' && { echo RED; exit 1; }; echo lane288-ok", "expect_exit": 0, "expect_regex": "lane288-ok", "timeout_s": 300}
```
