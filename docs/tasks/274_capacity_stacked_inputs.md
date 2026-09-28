# 274_capacity_stacked_inputs map-edge item inputs carry the maximum belt stack

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-274`, branch `lane/274`,
base tag `round-47-w1`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/first_stage.lua`, `tools/ckpt.lua save|list|uninterrupted`, `factorio`, or any full suite, whole sheet or
headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No
game item or entity name in `logic/`.** Every new test must FAIL on the base code where this task says "red on
base" (say so in its header comment); commit it red first.

## Explain very simply

Player ruling (2026-09-28): "Assume max possible stacking on any item input". Items that enter the blueprint from
the map edge (flow producer step `$external`, kind item) arrive on belts carrying the maximum belt stack; stacks stay
stacked on every belt they ride. So for those flows a belt carries `items_per_second x stack_max` (turbo 60/s x 4 =
240/s) and a lane `lane_items_per_second x stack_max`. Every other flow (made inside the blueprint) keeps 60/s.

Why: sheet `player-gray-magenta-science-10s` needs stone at 99.2/s from the map edge. Today groups splits it into 2
chunks, route folds the 2 edge feeds into one belt (`fold_edge_twins`, `logic/bp/route.lua` ~:2996-3082, merged
allocation with no capacity check = 99/s booked on a 60/s belt) and validate refuses 2 edge sources
(BP_V_SOURCE_DUPLICATE, rule "1 input item = 1 source", validate.lua ~:2663-2681). With stacking, one edge belt carries
it and the one-source rule holds.

stack_max: `logic/catalog.lua` adds `belt.stack_max` = max of `inserter_max_belt_stack_size` over inserter prototypes
(exists in 2.0.77 and 2.1.19 API, see docs/api/*.members.json), at least 1; when the engine gives nothing (offline
catalogs, prepared inputs without the field) use 4. `prepared_input.json` catalogs of golden cases have no field →
4 by default.

## What to build

1. New `logic/bp/belt.lua`: `Belt.stack_max(catalog)`, `Belt.is_external_item(flow)` (producers include step
   `$external`, not fluid), `Belt.capacity(catalog, flow, kind)` kind `belt`|`lane` → base x stack for external
   items, base otherwise. Pure functions, no state.
2. Every belt-capacity read uses it for the flow at hand:
   - `logic/bp/route.lua` `capacity_for` (~:582-587) (keep `input_belt_capacity` override semantics: an explicit input
     capacity still wins); `fold_edge_twins` (~:2996-3082): fold only when the merged allocation fits
     `capacity_for` of that flow.
   - `logic/bp/validate.lua` `segment_capacity` (~:920-923): segment of an external item flow → stacked.
   - `logic/bp/groups.lua` ~:664 (hand pairing capacity) and ~:2445-2451 (chunk count): external items use stacked.
   - `logic/bp/plan.lua` ~:598 lane capacity; `logic/bp/search.lua` ~:700 family input capacity.
   - `logic/catalog.lua` `belt.stack_max`.
3. Tests (red on base where marked):
   - `tests/test_belt_stack.lua` ST0 `Belt.capacity`: external item 60 → 240, internal item 60 → 60, fluid unchanged,
     explicit stack_max 2 → 120, missing field → 4.
   - ST1 (red on base): groups on a synthetic step with one external item input at 99/s, 4 machines → 1 chunk (not 2).
   - ST2: internal item 71.4/s split over 2 rows still 2 chunks.
   - ST3 (red on base): route: 2 edge twins of one external flow 99/s fold into one edge belt, segment total ≤ 240,
     one source port; internal twins over 60 still not folded.
   - ST4 (red on base): validate: external item segment 99/s on a 60/s belt → no BP_V_TRANSFER_CAPACITY; internal
     item 99/s → still refused.
4. Also keep green (one at a time, `timeout 90`): `test_route`, `test_route_budget`, `test_route_merge_feed`,
   `test_validate`, `test_validate_source_duplicate`, `test_validate_rows`, `test_groups_chunk_retry_ids`,
   `test_groups_faces_beacon_rows`, `test_bp_plan`, `test_search`, `test_catalog`, `test_no_item_names`,
   `test_no_runtime_require`, `test_locale_keys`.

## Files this lane owns

logic/bp/belt.lua, logic/catalog.lua, logic/bp/route.lua (ONLY `capacity_for` and `fold_edge_twins`),
logic/bp/validate.lua (ONLY `segment_capacity`), logic/bp/groups.lua (ONLY the two capacity reads), logic/bp/plan.lua
(ONLY ~:598), logic/bp/search.lua (ONLY ~:700), tests/test_belt_stack.lua, docs/tasks/274_capacity_stacked_inputs.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/274`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane274-tests", "command": "git diff --name-only round-47-w1 HEAD | grep -Ev '^(logic/bp/belt\\.lua|logic/catalog\\.lua|logic/bp/route\\.lua|logic/bp/validate\\.lua|logic/bp/groups\\.lua|logic/bp/plan\\.lua|logic/bp/search\\.lua|tests/test_belt_stack\\.lua|docs/tasks/274_capacity_stacked_inputs\\.md)$' | ( ! grep . ) && git diff --quiet round-47-w1 HEAD -- docs/tasks && for t in test_belt_stack test_route test_route_budget test_route_merge_feed test_validate test_validate_source_duplicate test_validate_rows test_groups_chunk_retry_ids test_groups_faces_beacon_rows test_bp_plan test_search test_catalog test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane274-tests-ok", "expect_exit": 0, "expect_regex": "lane274-tests-ok", "timeout_s": 3000}
{"name": "lane274-fast", "command": "out=$(timeout 120 lua5.2 tests/test_belt_stack.lua 2>&1); for c in ST0 ST1 ST2 ST3 ST4; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane274-ok", "expect_exit": 0, "expect_regex": "lane274-ok", "timeout_s": 600}
```

# bound: 3600s
