# 299_turn_flip_cases: game probe that writes the 20 tiny test sheets per game version

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-299`, branch `lane/299`,
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

Integrator runs this probe headless on Factorio 2.0.77 and 2.1.20 (space-age active in both); you only build and
check it offline.

1. `tests/game/lib/turn_flip_cases.lua` (new, plain data + pure functions, no engine calls at load):
   `CASES` = ordered list of 10 `{machine=, recipe=}` rows exactly as in the contract; `ids()` = 20 case ids
   `"<machine>-<recipe>-<1|4>"` sorted; `target_rate(one_machine_rate, n)` = `n * one_machine_rate * 0.999`
   (never rounds up to n+1 machines).
2. `tests/game/test_turn_flip_cases.lua` (new) — headless probe, modelled on `tests/game/test_capture.lua`
   (sheet row -> calculate -> Generation job through the player's own path, `S.bind`): for each version-available
   case: bind ONLY the case recipe (ingredients stay sheet inputs), force the machine to the case machine, no
   beacons, no modules, normal quality, no bots/roboports, `settings.input_edge="left"`, `output_edge="top"`,
   target = `target_rate` of the recipe's main product at one machine's crafting speed with n = 1 and n = 4.
   Take the prepared input the job builds (the same table the export capture stores: `handle.capture` /
   `logic/export_payload.lua:1326` `payload.prepared_input`) and collect it under `cases[id]`. Write
   `{"version": <script.active_mods.base>, "cases": {...}}` with `helpers.write_file("rrc_turn_flip_cases.json",
   helpers.table_to_json(...))`. A case whose machine or recipe is missing in this version is skipped and listed in
   an `"absent"` array (never an error). Offline (`RRC_OFFLINE`) it registers one test that checks the case list
   module loads.
3. `tests/test_turn_flip_cases.lua` (new, red on base) — offline shape checks, print markers:
   - TC1: `CASES` has the 10 contract rows in order; `ids()` gives 20 sorted ids.
   - TC2: `target_rate(r, 4) < 4 * r` and `> 3.99 * r`; `target_rate(r, 1) < r`.
   - TC3: a fixture checker `check_fixture(tbl)` (exported by the lib) accepts a minimal valid fixture (build one
     in the test from `tests/golden/cases/player-red-science-1s/prepared_input.json` with settings edges set) and
     rejects: missing version, case without catalog, edges not left/top.
   - TC4: `tests/game/test_turn_flip_cases.lua` loads offline via `lua5.2 tests/game/offline.lua` (run it from the
     test with io.popen, expect exit 0).
4. Register the new game test in `tests/game/index.lua` (same style as `test_material_cost`).

## Files this lane owns

`tests/game/lib/turn_flip_cases.lua`, `tests/game/test_turn_flip_cases.lua`, `tests/test_turn_flip_cases.lua`, `tests/game/index.lua`. 

## Commit, THEN check

Commit on `lane/299`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane299-tests", "command": "git diff --name-only round-54-base HEAD | grep -Ev '^(tests/game/lib/turn_flip_cases\\.lua|tests/game/test_turn_flip_cases\\.lua|tests/test_turn_flip_cases\\.lua|tests/game/index\\.lua)$' | ( ! grep . ) && for t in test_turn_flip_cases test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane299-tests-ok", "expect_exit": 0, "expect_regex": "lane299-tests-ok", "timeout_s": 3000}
{"name": "lane299-fast", "command": "out=$( (timeout 90 lua5.2 tests/test_turn_flip_cases.lua; timeout 90 lua5.2 tests/game/offline.lua tests/game/test_turn_flip_cases.lua) 2>&1); for c in TC1 TC2 TC3 TC4; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -Eq 'FAILED|FAIL |[1-9][0-9]* failed' && { echo RED; exit 1; }; echo lane299-ok", "expect_exit": 0, "expect_regex": "lane299-ok", "timeout_s": 300}
```

# bound: 5400s
