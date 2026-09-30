# 298_force_turn_flip: switch that forces every Block into one Turn and Flip

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-298`, branch `lane/298`,
base tag `round-54-base` (`the commit tag round-54-base points at (task files are in that commit)`), merge target `int/r54`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tools/turn_flip_census.sh`, `tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, `tests/test_drawn_e2e.lua`,
`tests/test_turn_flip_census.lua`, or any full suite, full census, whole sheet or headless run of any kind. No command
may take more than 60 s.** Run only single test files, one at a time, with `timeout 90 lua5.2 tests/<file>.lua` (lua5.2
ONLY, never lua5.4) or `timeout 90 python3 tests/<file>.py`; headless test files only offline: `timeout 90 lua5.2
tests/game/offline.lua tests/game/<file>.lua`. Never use `coroutine` or `math.random`. `require` only at file top
level. **No game item or entity name in `logic/`.** Deterministic: fixed scan order, ties broken by id string. Every
new test must FAIL on the base code where this task says "red on base" (say so in its header comment, with date
2026-09-30); commit it red first, then the code.

Read `CONTEXT.md` first: terms **Block**, **Row**, **Turn**, **Flip**, **Drawn pack**, **Layered pack**,
**Fallback**, **Box binding**, **Case**, **Fixture**, **Probe**, **Sheet sim**, **Engine rule**. Say "Turn" and
"Flip"; never "orient"/"orientation" in new names, comments or messages (glossary rule).

## Why (explain very simply)

A Block can Turn (0, 4, 8, 12 = north, east, south, west) and Flip (mirror). Round 53 found blueprints break when
Blocks are turned or flipped, but nothing could force a Turn or Flip, so it was never tested. This round builds tiny
test sheets, one per machine type, forced into all 8 Turn and Flip combos, judged offline and in the real game.

## Frozen contract (never change these shapes)

```lua
-- Switch: generation input settings (prepared_input.settings; generation.lua:1106 search_input_for copies settings)
settings.force_turn_flip = {turn = 0|4|8|12, flip = true|false}   -- nil = today's code path, same bytes
-- Effect when set: every Block's allowed_dirs = {turn} in BOTH pack modes (layered + drawn); flip=true -> before pack
-- each Block rebuilt with Groups.reorient(groups, block, {dir = 0, mirror = true}); a Block with any member whose
-- catalog entity has use_mirroring == false -> generation fails with error code "BP_FAIL_FLIP_FORBIDDEN" (no
-- blueprint); flip=true on a Block where mirroring moves no fluid connection (no member has can_flip) = no rebuild,
-- same build as flip=false; while set, no Fallback of any kind (drawn->layered, layered->MaxRects) runs.
-- Catalog entity (plain data): use_mirroring = false only when the engine prototype says false (2.1); else nil.

-- Fixture: tests/fixtures/turn_flip_cases_<2.0|2.1>.json
{ "version": "<factorio version>",
  "cases": { "<machine>-<recipe>-<1|4>": <prepared input table, same shape as
             tests/golden/cases/player-*/prepared_input.json, settings.input_edge="left", settings.output_edge="top"> } }
-- 10 recipes x machine count 1 and 4 = 20 cases:
--   assembling-machine-1/electronic-circuit, assembling-machine-2/empty-water-barrel, chemical-plant/plastic-bar,
--   chemical-plant/sulfuric-acid, oil-refinery/advanced-oil-processing, foundry/casting-iron,
--   foundry/iron-ore-melting, electromagnetic-plant/electrolyte, cryogenic-plant/fluoroketone,
--   biochamber/rocket-fuel

-- Census row (stdout, one line per case x Turn x Flip, fixed order: case id sorted, turn 0,4,8,12, flip 0,1):
CENSUS ver=<2.0|2.1> case=<id> turn=<0|4|8|12> flip=<0|1> result=<valid|forbidden|FAIL> code=<first error code or -> lanes=mixed=<n>,starved=<n>,bleed=<n>,dead=<n> sha=<first 8 hex of blueprint sha256 or ->
-- valid = generation ok + validate clean + lane_sim mixed=0 starved=0 bleed=0 dead=0
-- forbidden = generation failed with exactly BP_FAIL_FLIP_FORBIDDEN and flip=1; anything else = FAIL
```

## What to build

1. `logic/catalog.lua` (projection near :464-477): project `use_mirroring = false` onto the catalog entity when the
   prototype says `use_mirroring == false` (read under pcall; 2.0 has no such property -> leave nil). `can_flip` rule
   unchanged.
2. `logic/bp/search.lua`: read `settings.force_turn_flip` from `state.work.input.settings`. When set:
   - Before pack in BOTH pack paths (layered `Pack.begin` near :1587 and drawn near :1804), for every candidate
     Block: if any member machine's catalog entity has `use_mirroring == false` and `flip == true` -> fail generation
     with error code `BP_FAIL_FLIP_FORBIDDEN` (subject = machine name), no blueprint. Else if `flip == true` and some
     member has `can_flip` -> replace the Block with `Groups.reorient(state.work.groups, block, {dir = 0, mirror =
     true})` (reuse its cache; charge ops like the existing drawn orient phase near :1786-1795). If reorient returns
     nil, do NOT hide it: fail generation with `BP_FAIL_FLIP_REBUILD` (subject = block id) — this is a real defect
     other work fixes later.
   - Every Block `allowed_dirs = {turn}` (layered and drawn). In drawn mode skip the Orient.choose phase (Flip comes
     only from the switch).
   - `layered_fallback` (near :1487) returns false: no Fallback while forced. Generation fails with its normal code
     if nothing fits.
   Switch absent -> not one byte of behaviour changes.
3. `logic/bp/pack.lua`: honour a one-element `allowed_dirs` in both layered and drawn paths (drawn path near :1029
   today overwrites allowed_dirs with {0,4,8,12} or the drawing turn: when `input.forced_dir ~= nil` use
   `{input.forced_dir}`); search passes `forced_dir = turn` into `Pack.begin` input.
4. Register `BP_FAIL_FLIP_FORBIDDEN` and `BP_FAIL_FLIP_REBUILD` in `logic/bp/reason_codes.lua` (same list style as
   `BP_FAIL_NO_LAYOUT_GRID_LIMIT`, :24) and add keys `blueprint_fail_flip_forbidden` / `blueprint_fail_flip_rebuild` in `locale/{en,cs,ro}/locale.cfg` exactly like `blueprint_fail_no_layout_grid_limit` (en :221)
   (`test_locale_keys` must stay green).
5. `tests/test_force_turn_flip.lua` (new, red on base) — print each marker on pass:
   - TF1: forced turn 8 -> every placed Block direction 8, layered pack AND drawn pack (Search on a small in-test
     input; reuse helpers from `tests/test_pack_drawn.lua` / `tests/test_search_draw_phase.lua` style).
   - TF2: flip=true on a Block whose machine has `can_flip` -> placed machines carry `mirror == true`.
   - TF3: flip=true with member `use_mirroring == false` -> errors[1].code == "BP_FAIL_FLIP_FORBIDDEN", no blueprint.
   - TF4: flip=true on Block with no `can_flip` member -> same result as flip=false (compare placed entities).
   - TF5: switch absent -> `player-red-science-1s` bytes sha256 starts `6fea7eb3` (run
     `lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output
     <tmp>` once via io.popen like `tests/test_drawn_e2e.lua`; fast case, ~3 s, no slot needed).
   - TF6: forced + nothing fits (tiny grid) -> fails without Fallback (`result.search.fell_back` not true, no
     layered retry).
   - TF7: catalog projects `use_mirroring = false` from a mock prototype with `use_mirroring = false`; nil when the
     property is absent.

## Files this lane owns

`logic/bp/search.lua`, `logic/bp/pack.lua`, `logic/catalog.lua`, `logic/bp/reason_codes.lua`, `locale/en/locale.cfg`, `locale/cs/locale.cfg`, `locale/ro/locale.cfg`, `tests/test_force_turn_flip.lua`. 

## Commit, THEN check

Commit on `lane/298`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane298-tests", "command": "git diff --name-only round-54-base HEAD | grep -Ev '^(logic/bp/search\\.lua|logic/bp/pack\\.lua|logic/catalog\\.lua|logic/bp/reason_codes\\.lua|locale/en/locale\\.cfg|locale/cs/locale\\.cfg|locale/ro/locale\\.cfg|tests/test_force_turn_flip\\.lua)$' | ( ! grep . ) && for t in test_force_turn_flip test_search_draw_phase test_pack_drawn test_pack_layered test_orient test_catalog test_reason_codes_registry test_search_pipeline test_search_retry test_turned_block test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane298-tests-ok", "expect_exit": 0, "expect_regex": "lane298-tests-ok", "timeout_s": 3000}
{"name": "lane298-fast", "command": "out=$( (timeout 90 lua5.2 tests/test_force_turn_flip.lua) 2>&1); for c in TF1 TF2 TF3 TF4 TF5 TF6 TF7; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -Eq 'FAILED|FAIL |[1-9][0-9]* failed' && { echo RED; exit 1; }; echo lane298-ok", "expect_exit": 0, "expect_regex": "lane298-ok", "timeout_s": 300}
```

# bound: 5400s
