# 280_twins_rest every placement, power, beacon, hand, rate, identity and preflight rule gets twins

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-280`, branch `lane/280`,
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

Our validator (`logic/bp/validate.lua`) and preflight (`logic/bp/preflight.lua`) say what real Factorio will do.
Nobody checked them against the real game. A **twin** is one tiny factory (or one preflight request) written once
as data. Offline our judge rules on it; later the integrator builds the same twin in real headless Factorio and
looks. Both must agree. Read `docs/twins.md` FIRST: it is the frozen format. `tests/twins/transport/
bleed_last_belt_1.lua` and `_2.lua` are the worked example (a breach twin and its clean twin).

You write twin DATA files, plus the small code-registry fix in item 3. You never write engine code.

## What to build

1. For EVERY code below at least one **breach twin** (`truth = "defect"` or `"waste"`, `codes` = exactly the code
   set the judge returns) and one **clean twin** (`truth = "ok"`, `codes = {}`), `rule` = that code, `from =
   "<test file> <case name>"`. Real prototype names only (`assembling-machine-2`, `beacon`, `speed-module`,
   `medium-electric-pole`, `substation`, `roboport`, `inserter`, `long-handed-inserter`, `iron-gear-wheel`...).
   Every flow head on the grid edge (docs/twins.md). If the judge returns extra codes, change the twin until only
   the rule under test fires. Never change validator or preflight logic.

   - `stage = "validate"` (files under `tests/twins/place/`, `power/`, `beacon/`, `hands/`, `rate/`):
     BP_V_COLLISION (`check = "placeable"`), BP_V_ROBO_DISCONNECTED (`network`), BP_V_BEACON_COVERAGE_SHORT,
     BP_V_BEACON_REDUNDANT (`class = "waste"`), BP_V_SPEED_BEACON_ON_QUALITY (`beacon_effect`),
     BP_V_POWER_UNCOVERED (`powered`), BP_V_WIRE_ILLEGAL, BP_V_WIRE_DISCONNECTED (`network`),
     BP_V_INSERTER_GEOMETRY, BP_V_FLUID_INSERTER (`pickup_drop`), BP_V_TRANSFER_CAPACITY,
     BP_V_INSERTER_CAPACITY, BP_V_TARGET_SHORTFALL, BP_V_FLOW_IMBALANCE (`rate`), BP_V_MACHINE_IDENTITY,
     BP_V_MODULE_MISMATCH, BP_V_MACHINE_COUNT_MISMATCH (`rate`). Copy candidates from `tests/test_validate.lua`,
     `test_blueprint_physical_contract.lua`, `test_beacon_coverage.lua`, `test_validate_roboport_zone.lua`,
     `test_power.lua`, `test_inserter_geometry.lua`; put plan/catalog/ports/bindings/wires they need in `validator`.
   - `stage = "artifact"` (files under `tests/twins/artifact/`, `check = "artifact"`): the seven
     BP_V_ARTIFACT_* codes (INCOMPLETE, DIRECTION, MACHINE_COUNT, MACHINE_IDENTITY, MODULE_MISMATCH,
     BEACON_IDENTITY, WIRE_MISMATCH). Input shape: `tests/test_blueprint_physical_contract.lua:752-790`
     (`Validate.reconcile_artifact{artifact, plan, catalog}`).
   - `stage = "preflight"` (files under `tests/twins/preflight/`, `check = "prototype"`, `subject = {kind, name}` =
     the REAL vanilla or Space Age prototype that carries the fact, e.g. a recipe whose result spoils): every code in
     `tests/twins/required.lua` owned by L280 that starts `BP_REJ_`. Input shape: `tests/test_bp_preflight.lua:7-48`
     (`fixture` / `run`) and `tests/test_preflight_quality_facts.lua`.

2. Auditor counts (pin in `audit`, docs/twins.md "Audit"): for each key one twin pinning it `> 0` and one pinning
   `0`: `blueprint_audit` invalid_inserters, backward_hands, redundant_beacons. See counts with
   `lua5.2 tools/twin_bp.lua <twin> > /tmp/t.txt && python3 tools/blueprint_audit.py --json -q /tmp/t.txt`. If an
   auditor count looks wrong for the shape, pin what it gives and write `--AUDITOR-DOUBT: <why>` above `audit`.

3. Code registry (round 48 B9), in `logic/bp/reason_codes.lua` `ReasonCodes.VIOLATION`:
   - register `BP_V_TRANSFER_CAPACITY` and the seven `BP_V_ARTIFACT_*` codes (emitted by validate.lua, unregistered);
   - `BP_V_POWER_DISCONNECTED`, `BP_V_BELT_CAPACITY`, `BP_V_PIPE_CAPACITY` are registered but never emitted: delete
     them from `ReasonCodes.VIOLATION` AND delete their rows from `tests/twins/required.lua` (grep the repo first; if
     any code outside tests reads one of them, keep it and write a breach + clean twin that makes validate emit it —
     you may NOT change validate.lua, so if it cannot be emitted, delete it).
   - new test `tests/test_reason_codes_registry.lua` (red on base): every `"BP_V_..."` string in
     `logic/bp/validate.lua` is in `ReasonCodes.VIOLATION`, and every `BP_V_` entry there is emitted by validate.lua.

Done when `TWIN_OWNER=L280 lua5.2 tests/test_twins_coverage.lua` shows 0 failed.

## Files this lane owns

tests/twins/place/**, tests/twins/power/**, tests/twins/beacon/**, tests/twins/hands/**, tests/twins/rate/**,
tests/twins/artifact/**, tests/twins/preflight/**, tests/twins/required.lua (ONLY deleting the three dead rows),
logic/bp/reason_codes.lua (ONLY `ReasonCodes.VIOLATION`), tests/test_reason_codes_registry.lua,
docs/tasks/280_twins_rest.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/280`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane280-owned", "command": "git diff --name-only round-48-base HEAD | grep -Ev '^(tests/twins/(place|power|beacon|hands|rate|artifact|preflight)/[a-z0-9_]+\\.lua|tests/twins/required\\.lua|logic/bp/reason_codes\\.lua|tests/test_reason_codes_registry\\.lua|docs/tasks/280_twins_rest\\.md)$' | ( ! grep . ) && for t in test_reason_codes_registry test_no_item_names test_no_runtime_require test_locale_keys test_twins test_validate test_bp_preflight test_blueprint_physical_contract test_export_payload test_blueprint_pipeline test_generation_boundary_rules test_case_capture test_job_flow; do timeout 90 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane280-owned-ok", "expect_exit": 0, "expect_regex": "lane280-owned-ok", "timeout_s": 1200}
{"name": "lane280-cover", "command": "TWIN_OWNER=L280 timeout 90 lua5.2 tests/test_twins_coverage.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL coverage; exit 1; }; timeout 300 python3 -m unittest tests.tools.test_twins_audit 2>&1 | tail -1 | grep -q '^OK' || { echo FAIL audit; exit 1; }; echo lane280-cover-ok", "expect_exit": 0, "expect_regex": "lane280-cover-ok", "timeout_s": 600}
```

# bound: 3600s
