# 304_pack_pins: Drawn pack can pin Blocks in place and try one Block at one Turn

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-304`, branch `lane/304`,
base tag `round-55-base` (the commit that holds this task file), merge target `int/r55`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

# bound: 5400s

## You have about 90 minutes — do NOT stop early

Do not stop until every test below passes. Commit early, commit again, run the checks LAST.
**Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tools/turn_flip_census.sh`, `tools/ckpt.lua`, `tests/golden/generate.lua`, `factorio`, `tests/test_drawn_e2e.lua`,
or any full suite, census, whole golden sheet or headless run of any kind.** Single test files only:
`timeout 100 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4). Never use `coroutine` or `math.random`.
`require` only at file top level. **No game item or entity name in `logic/`.** Deterministic: fixed scan order,
ties broken by id string. Every new test must FAIL on the base code (say so in its header comment, date 2026-10-03);
commit it red first, then the code.

Read `CONTEXT.md` first: **Block**, **Turn**, **Drawn pack**, **Layer**, **Turn trial**. Say "Turn"; never
"orient"/"orientation" in new names, comments or messages.

## Why (explain very simply)

Drawn pack places Blocks, then a later step will try "what if this one Block was turned another way?". For that
try, every other Block must stay exactly where it was, and the one Block must use the asked Turn. Today drawn pack
cannot do either: it throws away any Turn a Block asks for. Measured by the integrator 2026-10-03 at 4720673:
a Block with `allowed_dirs={0}` (or 4, or 12) and `drawing.turn_of=8` was placed at dir 8 every time, because
`logic/bp/pack.lua:1031` overwrites every Block's `allowed_dirs` with `{forced_dir}` or `{0,4,8,12}`, and the
drawing's Turn also sets the Block size (`:613`, `:676`) and a penalty (`:747`).

## PRESERVE

- Every placement of a drawn or layered pack run with no `pins` and no `trial` stays byte-identical: all
  existing cases in the tests listed under "What done mean" keep passing, and no test count drops.
- `ReasonCodes.INTERNAL` keeps every code it has; `BP_P_TRIAL_PIN` gets no locale key (internal codes carry none,
  `tests/test_locale_keys.lua` L3).

## What to build (frozen seam — other code relies on exactly this)

`Pack.begin(input)` in drawn mode (`input.mode == "sugiyama"`) accepts two new optional fields:

- `input.pins = {[block_id] = {x=, y=, dir=}}`: each pinned Block is placed exactly at `x, y, dir` (size from
  `Grid.rotate_size(w, h, dir)`), BEFORE any other Block, and never searched. Placing it fills everything a searched
  placement fills: `state.placements`, `state.placement_by_id`, `state.placed_bbox` (pack.lua:822-835),
  `state.buffer_zones` (rotated, pack.lua:75-103), `state.port_cells` and port slots, so Blocks placed later see it.
- `input.trial = {block_id=, dir=}`: that one Block may use only `{dir}`; its size and its drawn penalty use `dir`,
  never `drawing.turn_of[block_id]`. It is placed LAST (after every pinned and unpinned Block), searched near its
  drawn target as today.
- A pin that overlaps another pin or an obstacle, or a trial Block that finds no legal origin, ends the pack:
  `state.failed`, error code `BP_P_TRIAL_PIN` (add it to `ReasonCodes.INTERNAL` in `logic/bp/reason_codes.lua`).
- Neither field given: every placement byte-identical to today (all existing tests unchanged).

## Tests (in `tests/test_pack_drawn.lua`, append; print each marker, e.g. `print("PD-PIN1")`, at the end of its passing case — the harness prints no case names)

- PD-PIN1: three Blocks, two pinned at given x,y,dir: they sit exactly there; the third is placed and does not
  overlap them.
- PD-PIN2: trial Block 2x4 at dir 4 (becomes 4x2) whose only room overlaps a pin -> `state.failed`, first error
  code `BP_P_TRIAL_PIN`.
- PD-PIN3: a pinned Block with buffer_zones and ports: after begin+step, `state.buffer_zones`, `state.port_cells`
  and `state.placed_bbox` include it exactly as if it had been searched to that spot.
- PD-PIN4: Block with `drawing.turn_of=8` and `input.trial={block_id=..., dir=4}` is placed at dir 4 with size
  `Grid.rotate_size(w,h,4)` (red today: placed dir 8).
- PD-PIN5: PD1-PD6 inputs with no `pins`/`trial` give the same placements as before (deep_equal against today's
  result computed in the test from the same input with the fields absent; and existing PD1-PD6 stay green).

## Files this lane owns

`logic/bp/pack.lua`, `logic/bp/reason_codes.lua`, `tests/test_pack_drawn.lua`.

## Commit, THEN check

Commit on `lane/304`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane304-tests", "command": "git diff --name-only round-55-base HEAD | grep -Ev '^(logic/bp/pack\\.lua|logic/bp/reason_codes\\.lua|tests/test_pack_drawn\\.lua)$' | ( ! grep . ) && run() { o=$(timeout 100 lua5.2 tests/$1.lua 2>&1); l=$(echo \\\"$o\\\" | tail -1); n=$(echo \\\"$l\\\" | sed -n 's/.*: \\\\([0-9][0-9]*\\\\) cases.*/\\\\1/p'); echo \\\"$l\\\" | grep -q ' 0 failed' || { echo FAIL $1; return 1; }; [ -n \\\"$n\\\" ] && [ \\\"$n\\\" -ge $2 ] || { echo COUNT $1 got=$n floor=$2; return 1; }; return 0; }; out=$(timeout 100 lua5.2 tests/test_pack_drawn.lua 2>&1); for m in PD-PIN1 PD-PIN2 PD-PIN3 PD-PIN4 PD-PIN5; do echo \"$out\" | grep -q \"$m\" || { echo NOMARK $m; exit 1; }; done; for p in test_pack_drawn:12 test_pack:30 test_pack_layered:3 test_pack_links:4 test_pack_buffer:8 test_pack_ticks:1 test_pack_budget:4 test_reason_codes_registry:1 test_force_turn_flip:8 test_search:46 test_search_draw_phase:4 test_search_retry:5 test_search_budget:6 test_search_stop:8 test_search_allowance:8 test_turned_block:6 test_no_item_names:1 test_no_runtime_require:3 test_locale_keys:3; do run ${p%%:*} ${p#*:} || exit 1; done && echo lane304-tests-ok", "expect_exit": 0, "expect_regex": "lane304-tests-ok", "timeout_s": 2400}
```
