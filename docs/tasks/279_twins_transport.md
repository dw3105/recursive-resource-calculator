# 279_twins_transport every belt, underground and fluid rule gets a clean twin and a breach twin

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-279`, branch `lane/279`,
base tag `round-48-base`, merge target `int/r48`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet or headless run of any kind.
No command may take more than 60 s.** Run only single test files, one at a time, with `timeout 90 lua5.2
tests/<file>.lua` (lua5.2 ONLY) or `timeout 90 python3 -m unittest tests.tools.test_twins_audit`. Never use
`coroutine`. `require` only at file top level. **No game item or entity name in `logic/`** (twin files are data
under `tests/`, names allowed there).

## Explain very simply

Our validator (`logic/bp/validate.lua`) says what real Factorio will do with a blueprint. Nobody checked it against
the real game. A **twin** is one tiny factory written once as data. Offline the validator judges it; later the
integrator builds the same twin in real headless Factorio and looks. Both must agree. Read `docs/twins.md` FIRST:
it is the frozen format. `tests/twins/transport/bleed_last_belt_1.lua` and `_2.lua` are the worked example (a
breach twin and its clean twin).

You write twin DATA files only. You never write engine code.

## What to build

For EVERY code below write at least one **breach twin** (`truth = "defect"` or `"waste"`, `codes` = exactly the
code set the validator returns) and one **clean twin** (`truth = "ok"`, `codes = {}`), `rule` = that code. Start
from the candidates the existing validator tests already build (copy their entities, convert to the twin format:
dir words, flows = real item names like `iron-plate`, `copper-plate`, `iron-gear-wheel`, fluids `fluid/water`), set
`from = "<test file> <case name>"`. Put every flow head (a belt no other belt feeds) on the grid edge
(`docs/twins.md`, validate.lua:1655) so no stray `BP_V_BELT_NO_SOURCE` fires. If the validator returns extra codes,
change the twin until only the rule under test fires. Never change validator code.

Codes (file under `tests/twins/transport/` or `tests/twins/fluid/`):
BP_V_BELT_BLEED (seed exists), BP_V_LANE_MIX, BP_V_BELT_NO_SOURCE, BP_V_SPLITTER_CHAIN,
BP_V_UNDERGROUND_SIDELOAD_BLOCKED, BP_V_UNDERGROUND_BACK_TO_BACK, BP_V_ROUTE_LOOP, BP_V_ROUTE_DISCONTINUOUS,
BP_V_ROUTE_MISSING, BP_V_TRANSFER_BROKEN, BP_V_TRANSPORT_UNUSED, BP_V_UNDERGROUND_UNPAIRED, BP_V_UNDERGROUND_RANGE,
BP_V_FLUID_DISCONNECTED, BP_V_FLUID_MIX, BP_V_FLUID_MIXING.

Source tests to copy candidates from: `tests/test_validate_bleed.lua`, `test_validate_splitter.lua`,
`test_validate_splitter_chain.lua`, `test_validate_splitter_rules.lua`, `test_validate_transport_shapes.lua`,
`test_validate_belt_no_source.lua`, `test_physical_witness.lua`, `test_validate_collector_witness.lua`,
`test_validate_side_feed_witness.lua`, `test_validate_witness_underground.lua`, `test_validate_ptg_sides.lua`,
`test_validate_fluid_mix.lua`, `test_red_green_fluid_ports.lua`, `test_validate.lua`.

`check` per twin (what the engine will look at, docs/twins.md table): belts, lanes, splitters, loops →
`flow_purity` or `rate`; undergrounds → `underground_pair`; pipes → `fluid_system`. `class`: `waste` for a rule whose
breach leaves the factory working but spends entities for nothing (TRANSPORT_UNUSED, SPLITTER_CHAIN), else `engine`.

Auditor counts (pin in the twin's `audit` table, docs/twins.md "Audit"): for each key below one twin pinning it
`> 0` and one pinning it `0`, inside the auditor's scope:
`blueprint_audit`: unpairable_underground_belt, unpairable_pipe_to_ground, unused_belt_tiles, unused_pipe_tiles,
sideload_blocked, back_to_back, cycles. `lane_sim`: mixed, starved, bleed (these count ONLY at an inserter pickup
that feeds a machine with a known recipe: put a machine with `recipe`, an inserter, and a `validator.catalog.recipe`
table in the twin; `tools/lane_sim.py:1-19`). See the counts any twin gives with
`lua5.2 tools/twin_bp.lua <twin> > /tmp/t.txt && python3 tools/blueprint_audit.py --json -q /tmp/t.txt` and
`lua5.2 tools/twin_bp.lua --catalog <twin> > /tmp/c.json && python3 tools/lane_sim.py /tmp/t.txt --input /tmp/c.json`.
If an auditor gives a count you believe is wrong for the shape, pin what it gives and write
`--AUDITOR-DOUBT: <why>` on the line above `audit` (the integrator judges it in real Factorio).

Done when `TWIN_OWNER=L279 lua5.2 tests/test_twins_coverage.lua` shows 0 failed.

## Files this lane owns

tests/twins/transport/** (new files; do not edit the two seed files), tests/twins/fluid/**,
docs/tasks/279_twins_transport.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/279`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane279-owned", "command": "git diff --name-only round-48-base HEAD | grep -Ev '^(tests/twins/transport/[a-z0-9_]+\\.lua|tests/twins/fluid/[a-z0-9_]+\\.lua|docs/tasks/279_twins_transport\\.md)$' | ( ! grep . ) && git diff --quiet round-48-base HEAD -- tests/twins/transport/bleed_last_belt_1.lua tests/twins/transport/bleed_last_belt_2.lua && for t in test_no_item_names test_no_runtime_require test_locale_keys test_twins; do timeout 90 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane279-owned-ok", "expect_exit": 0, "expect_regex": "lane279-owned-ok", "timeout_s": 600}
{"name": "lane279-cover", "command": "TWIN_OWNER=L279 timeout 90 lua5.2 tests/test_twins_coverage.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL coverage; exit 1; }; timeout 300 python3 -m unittest tests.tools.test_twins_audit 2>&1 | tail -1 | grep -q '^OK' || { echo FAIL audit; exit 1; }; echo lane279-cover-ok", "expect_exit": 0, "expect_regex": "lane279-cover-ok", "timeout_s": 600}
```

# bound: 3600s
