# 206_inserter_name groups: every hand is the inserter the player picked

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-206_inserter_name`, branch `lane/206_inserter_name`,
base tag `round-34-base`, merge target `int/r34`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data in `storage` only (save/load safe, no
closures, no metatables). Every unit test you write must finish in under 20 s and loop over `H.shapes()` (Factorio
2.0 and 2.1) when it touches the GUI or control.

Read `docs/contracts/round34.md` first: it is the contract. Your clauses: N1, N2, N3.

## Explain very simply

Player (1.1.77, 2026-09-25): inserter blueprint `~/share/RRC/player-inserter-10s-20260925-v1.txt` works but has
`inserter` ×8 (yellow) next to `fast-inserter` ×25 (blue, the pick) and `long-handed-inserter` ×4 (kept: the player
wants long-handed where reach 2 is needed). Cause: row hands at `logic/bp/groups.lua:1516` are named
`(input and input.inserter and input.inserter.name) or "inserter"`; every other hand uses
`inserter_size(catalog, input and input.inserter)` (`groups.lua:304`), which falls back to `catalog.inserter.name`.

## What to build

1. N1: row hands named through `inserter_size`.
2. N2: grep `logic/bp/groups.lua` for every string-literal entity-name fallback; route each through the catalog or
   settings pick. Write what you found and changed under "## Built".
3. N3: new `tools/entity_names.py` as in the contract (stdlib only; decode like `tools/blueprint_audit.py`
   `load_entities`).
4. Tests (red at base first): new `tests/test_groups_row_inserter_name.lua` (a row step with `catalog.inserter.name =
   "fast-inserter"` and no `input.inserter` → every row hand is `fast-inserter`); new `tests/test_entity_names.py`
   (unittest: a bp with a wrong inserter → `NAMES-BAD n=1`; all correct → `NAMES-OK`).

## Measure (one command each)

`sh tools/measure_sheet.sh player-inserter-10s` → `ok=true`, `mixed=0 starved=0 bleed=0`.
`sh tools/measure_sheet.sh player-red-science-1s` → `ok=true`, entities <= 169, `mixed=0 starved=0 bleed=0`.
`sh tools/measure_sheet.sh player-green-science-1s` → `ok=true`, entities <= 322, `mixed=0 starved=0 bleed=0`.
Then `tools/entity_names.py` on each sheet's bytes → `NAMES-OK` (the check block shows how to make bp.txt).

## Files this lane owns

logic/bp/groups.lua, tools/entity_names.py, tests/test_groups_row_inserter_name.lua, tests/test_entity_names.py, tests/test_groups.lua, tests/test_groups_hand_count.lua, docs/tasks/206_inserter_name.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/206_inserter_name`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane206-tests", "command": "git diff --name-only round-34-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|tools/entity_names\\.py|tests/test_groups_row_inserter_name\\.lua|tests/test_entity_names\\.py|tests/test_groups\\.lua|tests/test_groups_hand_count\\.lua|docs/tasks/206_inserter_name\\.md)$' | ( ! grep . ) && ! git diff round-34-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_groups_row_inserter_name test_groups test_groups_hand_count test_groups_fluid_row test_groups_long_hands; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && python3 -m unittest tests/test_entity_names.py 2>&1 | tail -1 | grep -q OK && echo lane206-tests-ok", "expect_exit": 0, "expect_regex": "lane206-tests-ok", "timeout_s": 2400}
{"name": "lane206-measure", "command": "sh tools/measure_sheet.sh player-inserter-10s | tail -1 | grep -E 'ok=true .*mixed=0 starved=0 bleed=0' && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-inserter-10s/prepared_input.json --output $d/r.json >/dev/null 2>&1 && python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/entity_names.py $d/bp.txt tests/golden/cases/player-inserter-10s/prepared_input.json | tail -1 | grep -q NAMES-OK && sh tools/measure_sheet.sh player-red-science-1s | tail -1 | awk '/ok=true/ && /mixed=0 starved=0 bleed=0/ {split($0,a,\"entities=\"); split(a[2],b,\" \"); if (b[1] <= 169) ok=1} END {exit !ok}' && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1 && python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/entity_names.py $d/bp.txt tests/golden/cases/player-red-science-1s/prepared_input.json | tail -1 | grep -q NAMES-OK && sh tools/measure_sheet.sh player-green-science-1s | tail -1 | awk '/ok=true/ && /mixed=0 starved=0 bleed=0/ {split($0,a,\"entities=\"); split(a[2],b,\" \"); if (b[1] <= 322) ok=1} END {exit !ok}' && d=$(mktemp -d) && lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-green-science-1s/prepared_input.json --output $d/r.json >/dev/null 2>&1 && python3 tools/blueprint_string.py $d/r.json -o $d/bp.txt >/dev/null && python3 tools/entity_names.py $d/bp.txt tests/golden/cases/player-green-science-1s/prepared_input.json | tail -1 | grep -q NAMES-OK && echo lane206-ok", "expect_exit": 0, "expect_regex": "lane206-ok", "timeout_s": 1800}
```

# bound: 3000s
