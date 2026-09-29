# 276_route_strict_ends in strict mode, a row belt end is seen by the end-feed guard, a row head crossed the wrong way is never a seed, and tidy never closes a ring

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-276`, branch `lane/276`,
base tag `round-49-base`, merge target `int/r49`. Host `legalcopilot-dev`.

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

Player sheet `player-magenta-science-10s` fails in game. Offline (legalcopilot-dev 2026-09-29, lua5.2, base
`90a3b81`) layout 6 routes but validate refuses 114 errors. Three router mistakes in `logic/bp/route.lua`:

- **B1 row belt end invisible.** `end_feed_bleeds` (~:2058) second loop needs `other.flow_id ~= nil` (~:2078).
  Row belts laid by `lay_belt_runs` (~:1220) get their flow only in `flow_ids` (`register_segment_flow` ~:1211);
  `flow_id` stays nil, so the guard never checks a row-belt end. Plastic row end (72,58) facing N; furnace
  underground entrance laid later at (72,57) facing W; both sides foreign ((71,58) copper S, (73,58) furnace N)
  -> 80 `BP_V_BELT_BLEED` + 1 `BP_V_UNDERGROUND_SIDELOAD_BLOCKED`.
- **B2 wrong-way row head is a free seed.** `begin_search` (~:2627) seed loop (~:2683-2703) queues the sink tile
  when a same-flow trunk crosses it in another heading, priced `SEEDED_SINK_LAST` (~:68) = 0. Stone trunk crosses
  stone-brick row port (40,4) (`travel_dir` 8 = south) as an underground EXIT facing east; demand ends there free;
  row 40:5..27 never fed -> 32 errors.
- **B3 tidy ring.** Same second loop skips same-flow older ends. A tidy trial puts an advanced-circuit exit (93,96)
  facing E in front of its own row end (93,95) facing S -> `BP_V_ROUTE_LOOP`.

**All three fire ONLY when `work.strict_ends` is true.** Measured: B1 always on changes routing of
`player-gray-magenta-science-10s` (it refuses a path at 38:34 that round 47 laid and later cleaned; the sheet then
fails). A separate search change (not this lane) sets `route_input.strict_ends = true` when validate refuses a layout
for belt shape and routes that same layout again. With the flag off, route must behave byte-for-byte as base.

Reference patch (ran in memory, gated exactly as below; whole magenta sheet `ok=true`, 2155 entities, 34785 ticks;
13 other golden sheets same bytes): `/home/dev_zaigraev_gmail_com/wt-rrc-int49/docs/tasks/r49_probes/p_strict.lua`
(route part) applying `f2_fix.lua` and `f3b_fix.lua` from the same folder. Probe format: file returns
`function(module_name, src) return new_src end`. Copy its logic; drop every `io.write`.

## What to build

1. `logic/bp/route.lua`:
   - Route work init (~:3565, beside `collectors = input.collectors ~= false`): `strict_ends = input.strict_ends == true`.
   - B1 + B3 in `end_feed_bleeds` second loop: the `f3b_fix.lua` NEW block, with the `flow_ids` fallback only when
     `work.strict_ends`, and the ring branch `elseif work.strict_ends and work.improve_state ~= nil and
     segment_has_flow(other, demand.flow_id) then` (walk `route_chain_walk` from `path[#path]` once per call;
     `local ring_tiles` before the path loop). With `strict_ends` false the loop must be exactly today's test.
   - B2: new top-level `local function row_seed_passes(work, demand, x, y, heading, segment)` placed just before
     `begin_search`: true only when `work.strict_ends`, `(x, y)` is the sink tile, `demand.sink.travel_dir ~= nil`,
     `heading ~= demand.sink.travel_dir`, sink is `row_port` or `perimeter`, AND the trunk passes through
     (`segment.underground` or `segment.splitter`, or the tile ahead in `heading` holds a segment with this flow).
     In the seed loop: `if row_seed_passes(...) then` skip the seed (no `enqueue_state`), else today's code.
   - Export `row_seed_passes` in `Route._test` (~:5146).
   - `route.lua` has 196 top-level `local` lines (Lua limit 200): add at most 1 (`row_seed_passes`).
   - Short comments with the measured numbers above + date 2026-09-29.
2. `tests/test_route_end_feed.lua` (keep EF1-EF4 unchanged; header comment: EF5 EF6 red on round-49-base):
   - EF5: world with `work.strict_ends = true`: row end `{kind="belt", fixed=true, flow_ids={plastic=true},
     direction=N, allocations={}}` (NO `flow_id`) at (72,58); belt copper dir S at (71,58); belt furnace dir N at
     (73,58); underground entrance furnace dir W at (72,57) with `underground=true`, `underground_exit_key` =
     key(61,57). `guard(w, {flow_id="furnace", kind="belt"}, {{x=73,y=58},{x=73,y=57},{x=72,y=57}}, {})` == true.
     Same world with `strict_ends` nil -> false.
   - EF6: `work.strict_ends = true`, `work.improve_state = {}`; row run flow A, fixed, `flow_ids` only, dir S at
     (93,90)..(93,95); new path of flow A: x=94 from y=96 up to y=90, then (93,90); underground exit A at (93,96) dir
     E laid; segments for the path laid with direction (build what `route_chain_walk` needs). Guard returns true.
   - EF7: EF6 with `improve_state = nil` -> false; EF6 with `strict_ends` nil -> false.
3. New `tests/test_route_row_seed.lua` (header: RS1 red on round-49-base):
   - RS1: `row_seed_passes` with `work.strict_ends = true`, sink `{row_port=true, travel_dir=8, x=40, y=4}`, flow
     stone; segment at 40:4 = underground exit dir E (`underground=true`) -> true.
   - RS2: same, `strict_ends` nil -> false. RS3: same, sink is an inserter port (no `row_port`, no `perimeter`) ->
     false. RS4: plain belt dir E at 40:4 and stone belt at 41:4 -> true; no same-flow segment at 41:4 -> false.
4. Also run and keep green (one at a time, `timeout 90`): `test_route`, `test_route_footprints`,
   `test_route_budget`, `test_route_improve`, `test_route_improve_waste`, `test_route_hop`, `test_route_hop_multi`,
   `test_route_hand_slide`, `test_route_ticks`, `test_route_keys`, `test_route_journal2`, `test_route_search_loop`,
   `test_route_shared_hand`, `test_route_belt_chain`, `test_route_row_reuse`, `test_route_rear_curve`,
   `test_no_item_names`, `test_no_runtime_require`, `test_locale_keys`.

## Files this lane owns

logic/bp/route.lua, tests/test_route_end_feed.lua, tests/test_route_row_seed.lua,
docs/tasks/276_route_strict_ends.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/276`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane276-tests", "command": "git diff --name-only round-49-base HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_end_feed\\.lua|tests/test_route_row_seed\\.lua|docs/tasks/276_route_strict_ends\\.md)$' | ( ! grep . ) && for t in test_route_end_feed test_route_row_seed test_route test_route_footprints test_route_budget test_route_improve test_route_improve_waste test_route_hop test_route_hop_multi test_route_hand_slide test_route_ticks test_route_keys test_route_journal2 test_route_search_loop test_route_shared_hand test_route_belt_chain test_route_row_reuse test_route_rear_curve test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane276-tests-ok", "expect_exit": 0, "expect_regex": "lane276-tests-ok", "timeout_s": 3000}
{"name": "lane276-fast", "command": "out=$(for t in test_route_end_feed test_route_row_seed; do lua5.2 tests/$t.lua 2>&1; done); for c in EF1 EF2 EF3 EF4 EF5 EF6 EF7 RS1 RS2 RS3 RS4; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -c ' 0 failed' | grep -q '^2$' && echo lane276-ok", "expect_exit": 0, "expect_regex": "lane276-ok", "timeout_s": 900}
```

# bound: 3600s
