# 190 (attempt 2) long-handed inserters end to end: far belts with two flows and far belts below the row

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-190`, branch `lane/190`,
base tag `round-29-lh2`, merge target `int/r29`. Host `legalcopilot-dev`.

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

Base (`round-29-lh2`) prints `entities 186` and `LANE-SIM mixed=0`. You must still print `LANE-SIM mixed=0` and `entities` <= 191; put the
printed entity count in your last commit message.

```sh
d=$(mktemp -d); lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/blueprint_audit.py $d/bp.txt | grep -E "^  (entities|belts) "; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1
```

## Explain very simply

A machine row whose recipe needs 3 or more item inputs gets a second belt (the far belt) one tile beyond the near
input belt, and each machine gets a long-handed inserter that reaches over the near belt to the far belt
(`docs/contracts/row_block.md` §Far belt, `docs/contracts/pipeline_r29.md` C4/C5). Groups already builds this
(`logic/bp/groups.lua`, `add_far`), and the hands reach validate. But the layout still fails: route does not lay and
feed the far belt correctly in every case. State on this base (measured 2026-09-24, probe below):
- k=1 (3 inputs, far belt with ONE flow): WORKS: delivers, 4 long-handed inserters, LANE-SIM mixed=0. Keep it working.
- k=2 (4 inputs, far belt with TWO flows side-fed at its head): `BP_V_LANE_MIX` on every long hand: both far flows
  ride one lane.
- k=3 (5 inputs, second far belt below the output belt): fails (lane mix on plain hands, route discontinuous).
Attempt 1 chased a probe bug (stone was added twice); the probe is fixed now. Make k=2 and k=3 work.

## Where the code is

- Probe: `lua5.2 tests/golden/long_hand_probe.lua <k> <out.json>` adds k raw inputs (stone, wood, coal) to the
  player's 4-machine science step: k=1 -> 3 inputs (far belt above), k=2 -> 4 inputs (far belt with two side feeds),
  k=3 -> 5 inputs (second far belt below the output belt). Then `python3 tools/blueprint_string.py out.json -o bp.txt`
  (exit 1 = not delivered; the reason codes are in `errors[1].reason_details` of out.json).
- Row runs in route: `belt_runs` with `far = true` (block frame -> `Groups.materialize` world frame). Search passes
  every block's `belt_runs` to route (`make_route_input`, `logic/bp/search.lua`); route lays row runs as fixed
  segments and binds each feed/rear port (look for `belt_runs`, `row_port`, `rear`, `feeds` in `logic/bp/route.lua`).
  A far run travels WEST (above) or EAST (below); its ports carry `far = true`.
- Validate: transfers per machine per flow (`check_physical_transfers`, `transfer_matches`, `transfer_cells`
  in `logic/bp/validate.lua`); long hands resolve reach 2 (`catalog.long_inserter`, else plain offsets doubled).
- You MAY change far-belt geometry in `groups.lua` (keep `test_groups_long_hands.lua` rules: nothing overlaps,
  reach 2 out and 2 in, near belt carries flows 1-2) if that is the simplest way; update `row_block.md` to match.

## What to build

1. Probe k=1, 2, 3 each delivers a blueprint that holds `long-handed-inserter` entities and passes
   `lane_sim.py` with `mixed=0`.
2. New `tests/test_long_hands_e2e.lua` (red at `round-29-lh2`): a small synthetic plan (one 3-machine step with 3 raw
   inputs and 1 output, plus a 4-input variant) through `Search` (see `tests/test_search.lua` / `tests/golden/generate.lua`
   for building search input) ends ok, and the layout has one long hand per machine whose pickup is a far-belt tile
   carrying its flow and whose drop is inside its machine.
3. The player's real sheet stays valid: `entities` <= 191, `LANE-SIM mixed=0`, first verdict ok.

## Checks (lua5.2 only, one file at a time)

`tests/test_long_hands_e2e.lua`, `tests/test_groups_long_hands.lua`, `tests/test_groups_rows.lua`, `tests/test_route_rows.lua`, `tests/test_validate_rows.lua`, `tests/test_rows_integration.lua`, `tests/test_route.lua`, `tests/test_blueprint_pipeline.lua`, `tests/test_search_pipeline.lua`, `tests/test_search_retry.lua`, the long-hand loop in the checks block, `sh tools/first_verdict.sh`, the
measure command.

## Files this lane owns

`logic/bp/route.lua`, `logic/bp/groups.lua`, `logic/bp/validate.lua`, `docs/contracts/row_block.md`, `tests/test_long_hands_e2e.lua`, `tests/test_groups_long_hands.lua`, `tests/test_route_rows.lua`, `tests/test_validate_rows.lua`, `tests/golden/long_hand_probe.lua`

Never touch anything else: not `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
`docs/contracts/pipeline_r29.md`, nor any test file not listed here.

## Commit, THEN check

Commit on `lane/190` with the measured entity counts (player sheet and probe k=1..3) in the message. **Run the checks
below as the very LAST action.**

## What done mean

```checks
{"name": "lane190-tests", "command": "git diff --name-only round-29-lh2 HEAD | grep -v '^docs/tasks/190' | grep -Ev '^(logic/bp/route\\.lua|logic/bp/groups\\.lua|logic/bp/validate\\.lua|docs/contracts/row_block\\.md|tests/test_long_hands_e2e\\.lua|tests/test_groups_long_hands\\.lua|tests/test_route_rows\\.lua|tests/test_validate_rows\\.lua|tests/golden/long_hand_probe\\.lua)$' | ( ! grep . ) && ! git diff round-29-lh2 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_long_hands_e2e test_groups_long_hands test_groups_rows test_route_rows test_validate_rows test_rows_integration test_route test_blueprint_pipeline test_search_pipeline test_search_retry; do lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane190-tests-ok", "expect_exit": 0, "expect_regex": "lane190-tests-ok", "timeout_s": 1500}
{"name": "lane190-long", "command": "for k in 1 2 3; do d=$(mktemp -d); lua5.2 tests/golden/long_hand_probe.lua $k $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null || { echo NO-DELIVERY $k; exit 1; }; grep -q . $d/bp.txt; python3 -c \"import base64,zlib,json,sys;b=json.loads(zlib.decompress(base64.b64decode(open(sys.argv[1]).read().strip()[1:])))['blueprint'];sys.exit(0 if any(e['name']=='long-handed-inserter' for e in b['entities']) else 1)\" $d/bp.txt || { echo NO-LONG $k; exit 1; }; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1 | grep -q 'mixed=0' || { echo LANE-MIX $k; exit 1; }; echo LONG-OK $k; done && echo lane190-long-ok", "expect_exit": 0, "expect_regex": "lane190-long-ok", "timeout_s": 900}
{"name": "lane190-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc190-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc190-first.txt && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1; python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/blueprint_audit.py $d/bp.txt | grep -E '^  (entities|belts) ' | tee /tmp/rrc190-measure.txt; python3 /home/dev_zaigraev_gmail_com/.claude/plans/rrc-round-22-probes/lane_sim.py $d/bp.txt | tail -1 | grep -q 'mixed=0' && awk '/entities/ {exit !($2 <= 191)}' /tmp/rrc190-measure.txt && echo lane190-probe-ok", "expect_exit": 0, "expect_regex": "lane190-probe-ok", "timeout_s": 600}
```

# bound: 3000s
