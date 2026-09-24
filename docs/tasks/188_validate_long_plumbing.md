# 188 validate: roboport outside buffer zones, ring bump; long-handed inserter pick and facts

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-188`, branch `lane/188`,
base tag `round-29-base`, merge target `int/r29`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 45 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its tests pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), the
probe `sh tools/first_verdict.sh` (~10 s) and the measure command below (~60 s). Never use `coroutine` (Factorio has
none). Plain data state only (the job is resumable across game ticks).

Read `docs/contracts/pipeline_r29.md` first: it is the contract. Your clauses are named below; code EXACTLY the
field names it gives, other lanes code against the same names.

## Measure (player's real sheet)

Base (`round-29-base`) prints `entities 174` and `LANE-SIM mixed=0`. You must still print `LANE-SIM mixed=0`; put the
printed entity count in your last commit message.

```sh
d=$(mktemp -d); lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/blueprint_audit.py $d/bp.txt | grep -E "^  (entities|belts) "; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1
```

## Explain very simply

Two small things. (a) The validator must refuse a roboport inside any machine buffer zone, and use the widened
ring when a retry asks for it. (b) The player picks a long-handed inserter in the blueprint dialog like any other
building; the catalog captures its geometry so the generator and the validator know its reach.

## Where the code is

- `logic/bp/buffer.lua` header comment (lines 4-5 allow roboports: change per C2).
- `logic/bp/validate.lua`: `check_buffer_zones` (~898, `Buffer.ring` at ~909), robo entities, `transfer_cells`
  (~1341, offsets from `info.spec` falling back to `catalog.inserter`), phase list (~2455).
- `logic/bp/reason_codes.lua` (~34 `BP_V_BUFFER_ZONE`).
- `logic/catalog.lua` `build_inserter` (~734), `validate_inserter_geometry` (~402).
- `logic/bp/settings.lua` `INFRASTRUCTURE` (~17), defaults (~153), `Settings.validate` (~269).
- `logic/export_payload.lua` (~105, ~178 capture fields). `logic/bp/generation.lua` (~372, ~427 settings pass).
- `gui/blueprint_dialog.lua` `INFRASTRUCTURE` (~20), `validate_settings` (~191). `locale/*/locale.cfg`.
  Engine GUI rule: sibling element names must be unique (duplicate names crashed 1.1.15).

## What to build

1. C1 in validate: ring = `Buffer.ring(...) + (input.ring_bump or 0)`.
2. C2 in validate: `BP_V_BUFFER_ROBOPORT` when a machine zone intersects a roboport footprint; register the code;
   buffer.lua comment.
3. C5: `catalog.long_inserter` captured like `catalog.inserter` (same fields, same geometry validation); settings key
   `long_inserter` (default `long-handed-inserter`, type inserter); dialog button `hxrrc_blueprint_long_inserter_button`
   with locale in en/cs/ro; `validate_settings` checks it; export payload captures it; generation passes it to the
   catalog.
4. C5 in validate: an inserter entity whose name equals `catalog.long_inserter.name` uses its offsets.
5. Tests, red at `round-29-base` first:
   - new `tests/test_validate_roboport_zone.lua`: machine ring touching a roboport -> `BP_V_BUFFER_ROBOPORT`; one
     tile further -> clean; `ring_bump = 1` turns a clean layout into a `BP_V_BUFFER_ZONE` / robo error.
   - new `tests/test_long_inserter_catalog.lua`: catalog built with a long inserter prototype (pickup/drop 2 tiles)
     holds `long_inserter` facts; settings default and validate; validate accepts a long hand reading a belt 2
     tiles out and dropping 2 tiles in, refuses it when treated as plain.
   - update `test_buffer`, `test_validate_buffer`, `test_bp_settings` as needed.

## Checks (lua5.2 only, one file at a time)

`tests/test_validate_roboport_zone.lua`, `tests/test_long_inserter_catalog.lua`, `tests/test_buffer.lua`, `tests/test_validate_buffer.lua`, `tests/test_bp_settings.lua`, `tests/test_control.lua`, `tests/test_export_payload.lua`, `tests/test_catalog.lua`, `tests/test_validate_rows.lua`, then `sh tools/first_verdict.sh` (must print `ok=true`), then the
measure command (must print `LANE-SIM mixed=0`).

## Files this lane owns

`logic/bp/buffer.lua`, `logic/bp/validate.lua`, `logic/bp/reason_codes.lua`, `logic/catalog.lua`, `logic/bp/settings.lua`, `logic/export_payload.lua`, `logic/bp/generation.lua`, `gui/blueprint_dialog.lua`, `locale/en/locale.cfg`, `locale/cs/locale.cfg`, `locale/ro/locale.cfg`, `tests/test_validate_roboport_zone.lua`, `tests/test_long_inserter_catalog.lua`, `tests/test_buffer.lua`, `tests/test_validate_buffer.lua`, `tests/test_bp_settings.lua`, `tests/test_control.lua`, `tests/test_export_payload.lua`, `tests/test_catalog.lua`

Never touch anything else: not `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
`docs/contracts/pipeline_r29.md`, nor any test file not listed here. A test file listed here that tests code you
deleted is deleted or rewritten by you.

## Commit, THEN check

Commit on `lane/188` with the measured entity count in the message. **Run the two checks below as the very LAST
action.**

## What done mean

```checks
{"name": "lane188-tests", "command": "git diff --name-only round-29-base HEAD | grep -v '^docs/tasks/188' | grep -Ev '^(logic/bp/buffer\\.lua|logic/bp/validate\\.lua|logic/bp/reason_codes\\.lua|logic/catalog\\.lua|logic/bp/settings\\.lua|logic/export_payload\\.lua|logic/bp/generation\\.lua|gui/blueprint_dialog\\.lua|locale/en/locale\\.cfg|locale/cs/locale\\.cfg|locale/ro/locale\\.cfg|tests/test_validate_roboport_zone\\.lua|tests/test_long_inserter_catalog\\.lua|tests/test_buffer\\.lua|tests/test_validate_buffer\\.lua|tests/test_bp_settings\\.lua|tests/test_control\\.lua|tests/test_export_payload\\.lua|tests/test_catalog\\.lua)$' | ( ! grep . ) && ! git diff round-29-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_validate_roboport_zone test_long_inserter_catalog test_buffer test_validate_buffer test_bp_settings test_control test_export_payload test_catalog test_validate_rows; do lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane188-tests-ok", "expect_exit": 0, "expect_regex": "lane188-tests-ok", "timeout_s": 1500}
{"name": "lane188-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc188-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc188-first.txt && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/blueprint_audit.py $d/bp.txt | grep -E '^  (entities|belts) ' | tee /tmp/rrc188-measure.txt; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1 | grep -q 'mixed=0' && echo lane188-probe-ok", "expect_exit": 0, "expect_regex": "lane188-probe-ok", "timeout_s": 600}
```

# bound: 2400s
