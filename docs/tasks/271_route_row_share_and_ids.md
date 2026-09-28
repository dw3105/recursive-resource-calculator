# 271_route_row_share_and_ids row belts book own share, row endpoints are per block, a path never ends on a trunk crossing a row head

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-271`, branch `lane/271`,
base tag `round-47-base`, merge target `int/r44`. Host `legalcopilot-dev`.

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

Sheet `player-gray-magenta-science-10s` (grid 104x154) is refused by validate with hundreds of errors. Three of the
causes are in `logic/bp/route.lua` (measured legalcopilot-dev 2026-09-28, lua5.2, base `06ba0a7`):

- **B1 row belt books whole flow.** `lay_belt_runs` (~:1187) gives every tile of a row belt run an allocation for
  EVERY demand of that flow on the sheet, not only the demands whose endpoint is on this row. A flow split over 2 rows
  (rail 2 x 35.7/s) is booked 71.4/s on each 60/s belt → 132 BP_V_TRANSFER_CAPACITY + 65 BP_V_TARGET_SHORTFALL.
  Fix (reference `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/p_runbook.lua`, proven: 334 → 137 errors, bytes of 13 golden sheets
  unchanged): book only demands whose run-side endpoint (`sink` for role `in`, `source` for `out`) lies on a
  "near" tile of this run: head and its 4 neighbours, every run tile, the 4 neighbours of first and last run tile,
  every feed `side_tile`. If no demand of that flow is near, keep the old whole-flow booking.
- **B4 row port ids repeat across blocks.** Row ports are named `row:in:<flow>`, `row:out:<flow>`, `row:in:rear`
  with no block in the name (groups.lua ~2119-2137). `work.endpoint_by_id[endpoint.port_id] = endpoint` (~:3337,
  :3343) keeps the LAST block. Two blocks fed from one source at one rate (electric furnace → 2 production rows)
  give two bindings with identical keys (same source port, sink port, rate); every improve lookup picks the first:
  `find_binding` (~:4100-4104), demand match (~:4323-4325), multi-binding lookup (~:4137), order keys (~:4225,
  :4235, :4252, :4340); `all_bindings_reach_sinks` (~:1765-1766), `binding_path` (~:3673-3674) and ~:4290 walk the
  wrong block's tile. Improve lifted the shared furnace trunk and lost 17 belts → 15 discontinuous + 56 unused +
  16 lane-mix. Fix (spec, no probe file):
  - `local function ep_lookup(work, port_id, block_id, flow_id, role)` before `sink_key` (~:598): when block_id and
    flow_id given, search `work.endpoint_index[flow_id][role]` for `e.port_id == port_id and e.block_id ==
    block_id`; else fall back to `work.endpoint_by_id[port_id]`.
  - bindings record `sink_block_id = demand.sink.block_id` (~:1906, ~:2112) and `source_block_id =
    demand.source.block_id` (~:2165).
  - lookups at ~:1765, :1766, :3673, :3674, :4290 use `ep_lookup(work, binding.<x>_port_id, binding.<x>_block_id,
    binding.flow_id, "out"|"in")`.
  - key lists (~:4235, :4340) gain `binding.sink_block_id` as 4th element; key strings (~:4225, :4252) append
    `"|" .. tostring(<4th>)`; matches (~:4103, :4325, :4137) add `and (wanted[4] == nil or <candidate block> ==
    wanted[4])`.
  - rear-merge setup that loops `pairs(endpoint_by_id)` registers every block's `row:in:rear` (keep a per-block list).
  Check the endpoint normaliser really sets `endpoint.block_id`; if not, set it there from the block.
- **B7 path ends on a crossing trunk.** In `append_normal_path` the existing-segment branch (`if segment then`,
  ~:2007) lets a path END on a belt already laid in another heading. For a row feed port (belt head) the items then
  pass by: stone trunk north across stone-brick row head (7,104) → row gets nothing. Fix (reference
  `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/p_rowreuse.lua`): when `index == #path`, belt demand, `demand.sink.row_port`,
  `demand.sink.role == "in"`, `travel_dir` known, cell is the sink tile, segment not splitter/underground and
  `segment.direction ~= demand.sink.travel_dir` → `return reject("occupied")`. Static scan: fires on 1 of 32 row
  demands on the sheet (the broken one).

Probe patch format: file returns `function(module_name, src) return new_src end`; the reference files are what ran.

## What to build

1. `tests/test_route_row_book.lua` RB1 (red on base): synthetic route input, one flow, 2 row blocks each with an
   `in` belt run, 2 demands of 35.7/s from one source, belt 60/s. After `Route.begin` + demand build
   (`Route.step` until `work.demand_build_done`), every run segment's allocation total ≤ 60 and each run carries
   only its own demand. RB2: a run whose flow has no near demand keeps old whole-flow booking.
2. `tests/test_route_row_ids.lua` RI1 (red on base): 2 row blocks with the same row port id `row:in:<flow>`, one
   source, same rate: after routing + tidy, 2 distinct bindings exist and `binding_path` of each reaches its OWN
   block's sink tile. RI2: `ep_lookup` falls back to `endpoint_by_id` when block id missing.
3. `tests/test_route_row_reuse.lua` RR1 (red on base): trunk of the same flow already crossing the row head tile in
   another heading; `append_normal_path` for the row demand whose path ends on that tile is refused `occupied`.
   RR2: same path ending on a tile whose belt faces `travel_dir` is kept.
4. `logic/bp/route.lua`: B1, B4, B7, short comments with measured numbers + date.
5. Also run and keep green (one at a time, `timeout 90`): `test_route`, `test_route_budget`, `test_route_improve`,
   `test_route_improve_waste`, `test_route_hop`, `test_route_hop_multi`, `test_route_hand_slide`, `test_route_ticks`,
   `test_route_keys`, `test_route_journal2`, `test_route_search_loop`, `test_route_shared_hand`, `test_route_belt_chain`,
   `test_route_merge_trial` (if present), `test_no_item_names`, `test_no_runtime_require`, `test_locale_keys`.

## Files this lane owns

logic/bp/route.lua, tests/test_route_row_book.lua, tests/test_route_row_ids.lua, tests/test_route_row_reuse.lua,
docs/tasks/271_route_row_share_and_ids.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/271`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane271-tests", "command": "git diff --name-only round-47-base HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_row_book\\.lua|tests/test_route_row_ids\\.lua|tests/test_route_row_reuse\\.lua|docs/tasks/271_route_row_share_and_ids\\.md)$' | ( ! grep . ) && git diff --quiet round-47-base HEAD -- docs/tasks && for t in test_route_row_book test_route_row_ids test_route_row_reuse test_route test_route_budget test_route_improve test_route_improve_waste test_route_hop test_route_hop_multi test_route_hand_slide test_route_ticks test_route_keys test_route_journal2 test_route_search_loop test_route_shared_hand test_route_belt_chain test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane271-tests-ok", "expect_exit": 0, "expect_regex": "lane271-tests-ok", "timeout_s": 3000}
{"name": "lane271-fast", "command": "out=$(for t in test_route_row_book test_route_row_ids test_route_row_reuse; do lua5.2 tests/$t.lua 2>&1; done); for c in RB1 RB2 RI1 RI2 RR1 RR2; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -c ' 0 failed' | grep -q '^3$' && echo lane271-ok", "expect_exit": 0, "expect_regex": "lane271-ok", "timeout_s": 900}
```
