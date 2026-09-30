# 300_turn_flip_census: census runner: every tiny sheet in every Turn and Flip, offline and in the game lab

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-300`, branch `lane/300`,
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

1. `tools/turn_flip_census.lua` (new): `lua5.2 tools/turn_flip_census.lua <fixture.json> [--case <id>] [--turn
   <t>] [--flip <0|1>] [--export <dir>]`. For every selected case x Turn x Flip (contract order): copy the case's
   prepared input, set `settings.force_turn_flip = {turn=, flip=}`, write it to a temp file named
   `turn_flip_<case>_<t>_<f>.json` under `os.getenv("TMPDIR") or "/tmp"`, run `lua5.2 tests/golden/generate.lua
   --input <tmp> --output <r.json>` (io.popen, inherit env), take the blueprint string exactly as
   `tools/sheet_verdict.sh` does, run `python3 tools/lane_sim.py <bp.txt> --input <tmp>` and parse
   mixed/starved/bleed/dead, print one CENSUS row. `--export <dir>`: for valid rows write
   `<dir>/<ver>/<case>_<t>_<f>.bp.txt` + `.ports.json` via `python3 tools/sheet_ports.py` (same call
   `tools/game_stage.sh` / round 48 capture flow uses). Exit 0 always; summary line `CENSUS-SUMMARY rows=<n>
   valid=<n> forbidden=<n> fail=<n>`.
2. `tools/lib/slow_guard.lua`: a generate input path whose basename starts `turn_flip_` is a fast check (no slot),
   like `fast_cases`; keep every other rule byte-identical.
3. `tools/turn_flip_census.sh` (new, integrator only): for ver in 2.0 2.1: census with `--export`, stage exported
   sheets for the game lab, run `tests/game/test_turn_flip_sims.lua` in FULL mode (`RRC_TURN_FLIP_FULL=1`) on that
   version via `tools/game_test.sh`; print both summaries. Never run it yourself.
4. `tests/game/test_turn_flip_sims.lua` (new): Sheet sim of turn-flip sheets with `tests/game/lib/lab.lua` exactly as
   `tests/game/test_sheets.lua` does (build, power, feed ports full, run, count; pass = every target >= 0.95 x rate,
   no foreign item at sink, every entity placed). Sheets come from an embedded index (same mechanism as
   `sheets_index`, extend `tools/game_stage.sh` to embed `tests/fixtures/turn_flip_sheets/<ver>/*`). Default: sample
   = every case with turn 8, flip 1 (and flip 0 where flip is forbidden) = up to 40 per version; `RRC_TURN_FLIP_FULL=1`
   = every staged sheet. Offline: one test checking the lib loads.
5. `tests/test_turn_flip_census.lua` (new, SUITE test, never run it yourself): for each existing
   `tests/fixtures/turn_flip_cases_<ver>.json`, run the tool over every row; fail listing every FAIL row. No fixture
   yet -> prints `skip: no turn_flip fixtures` and passes.
6. `tests/test_turn_flip_census_tool.lua` (new, red on base) — uses a mini fixture built IN the test from
   `tests/golden/cases/player-red-science-1s/prepared_input.json` (1 case, id `mock-red-1`, edges left/top):
   - CT1: `--case mock-red-1 --turn 0 --flip 0` prints exactly one CENSUS row with all contract fields in order.
   - CT2: row parser (exported by a small lib `tools/lib/census_row.lua`) round-trips a row; `result` classification:
     generation error BP_FAIL_FLIP_FORBIDDEN + flip 1 -> forbidden; any other error -> FAIL; lanes non-zero -> FAIL.
   - CT3: slow_guard treats `/tmp/turn_flip_x_0_0.json` as fast and still refuses a non-fast golden input.
   - CT4: `--export` writes bp.txt + ports.json for a valid row (use the CT1 row).
   (CT1/CT4 run generate once on the fast red-1s input, ~3 s each; allowed.)

## Files this lane owns

`tools/turn_flip_census.lua`, `tools/lib/census_row.lua`, `tools/lib/slow_guard.lua`, `tools/turn_flip_census.sh`, `tools/game_stage.sh`, `tests/game/test_turn_flip_sims.lua`, `tests/test_turn_flip_census.lua`, `tests/test_turn_flip_census_tool.lua`. Do not register the new game test in tests/game/index.lua (another file owner does that at merge).

## Commit, THEN check

Commit on `lane/300`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane300-tests", "command": "git diff --name-only round-54-base HEAD | grep -Ev '^(tools/turn_flip_census\\.lua|tools/lib/census_row\\.lua|tools/lib/slow_guard\\.lua|tools/turn_flip_census\\.sh|tools/game_stage\\.sh|tests/game/test_turn_flip_sims\\.lua|tests/test_turn_flip_census\\.lua|tests/test_turn_flip_census_tool\\.lua)$' | ( ! grep . ) && for t in test_turn_flip_census_tool test_slow_guard test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && timeout 300 python3 tests/test_lane_sim.py 2>&1 | tail -3 | grep -q '^OK' || { echo FAIL test_lane_sim; exit 1; } && echo lane300-tests-ok", "expect_exit": 0, "expect_regex": "lane300-tests-ok", "timeout_s": 3000}
{"name": "lane300-fast", "command": "out=$( (timeout 90 lua5.2 tests/test_turn_flip_census_tool.lua) 2>&1); for c in CT1 CT2 CT3 CT4; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -Eq 'FAILED|FAIL |[1-9][0-9]* failed' && { echo RED; exit 1; }; echo lane300-ok", "expect_exit": 0, "expect_regex": "lane300-ok", "timeout_s": 300}
```

# bound: 5400s
