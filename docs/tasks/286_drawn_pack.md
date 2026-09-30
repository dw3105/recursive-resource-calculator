# 286_drawn_pack: pack aims each Block at its drawn spot (RRC_PACK=sugiyama)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-286`, branch `lane/286`,
base tag `round-51-base`, merge target `int/r51`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tests/golden/generate.lua`, `tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet
or headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine` or `math.random`. `require` only at file
top level. **No game item or entity name in `logic/`.** Every new test must FAIL on the base code where this task
says "red on base" (say so in its header comment); commit it red first.

## Explain very simply

Read `CONTEXT.md` section "Layout" first (Block, Flow graph, Source, Output, Layer, Turn, Flip, Crossing).

New flagged pack mode `RRC_PACK=sugiyama` ("drawn pack"). Search draws the Flow graph first
(`logic/bp/flow_draw.lua`, frozen contract in its top comment; today a skeleton: longest-path Layers, input-order
ranks, Turn 0). Then fluid Blocks may get machines turned/flipped (`logic/bp/orient.lua` `Orient.choose` +
`Groups.reorient`, frozen contracts; today skeletons that change nothing). Then Pack places each Block near its
drawn spot. You wire all three and write the drawn target + penalties in Pack. Other lanes fill the drawing and
orient bodies later; your code must only use the contract fields.

Flag off (no `RRC_PACK`, or `layered`, or `maxrects`) must stay byte-identical to today. Measured 2026-09-30: forcing
any Block Turn (N/E/S/W) on real sheets still gives valid layouts, so all 4 Turns are safe to offer.

Today (`logic/bp/pack.lua`): `Pack.layered = os.getenv("RRC_PACK") ~= "maxrects"` (:545-547); `layered_order`
(:549-578) sorts by longest-path layer; `layered_target` (:580-620) aims x one tile past earlier layers, y at mean
partner port row (assumes columns run right, uses unrotated `block.h`/`attach_dy`); `layered_legal` (:623) and
`layered_scan` (:647, Manhattan ring walk, `EXTRA` rings past first legal origin, across `allowed_dirs`); `better`
(:182) compares `link_cost` first; `linked_cost` (:325). `Pack.begin` (:872-926), `Pack.step` (:928; layered branch
~:944). Search (`logic/bp/search.lua`): `candidate_links` (:1503-1541), `prepare_candidate` (:1544-1562) calls
`Pack.begin`; `pack_layered` / `layered_fallback` (:1478-1489); `run_stage` (:1223-1242) charges ops of any stage
whose state has `done`; phase dispatch `elseif state.phase == "pack"` (~:1715).

## What to build

1. `logic/bp/pack.lua`:
   - `Pack.mode = os.getenv("RRC_PACK") or "layered"` (keep `Pack.layered` meaning exactly: true unless
     `"maxrects"`; `"sugiyama"` also counts as layered for fallback). Tests set `Pack.mode` directly.
   - `Pack.begin` input gains `mode` ("sugiyama" or nil) and `drawing` (FlowDraw `state.result`) and `input_edge`.
     Only when `mode == "sugiyama"`: block order = by (`layer_of`, `rank_of`), unknown ids last in input order;
     every block `allowed_dirs = {0, 4, 8, 12}`; target = drawn target; cost adds penalty. Otherwise every line of
     today's path runs unchanged.
   - Drawn target (new function; any `input_edge`): flow axis points away from `input_edge` (left: +x, right: -x,
     top: +y, bottom: -y). Layer L band start along flow axis = sum over Layers < L of (max rotated depth of Blocks in
     that Layer, using `Grid.rotate_size` with preferred Turn `turn_of[id]`) + `Pack.DRAWN_GAP` (= 4) each. Across
     axis: rank offset = sum of rotated widths + `Pack.DRAWN_GAP` of Blocks with smaller rank in same Layer, plus 1
     tile per Source/Output/dummy with smaller rank there (read their ranks from `drawing.sources/outputs/dummies`).
     Clamp target inside `area`.
   - Penalty (added to `link_cost` before `better`): P = candidate's rotated across-axis width.
     `P * (broken + covered + turn_off)`: broken = placed Blocks of same Layer whose rank order vs this Block is the
     reverse of their across-axis order; covered = dummies whose drawn tile (their band, their rank offset) lies
     inside the candidate rect; turn_off = 1 when candidate dir ~= `turn_of[id]`.
   - Everything stays sliceable exactly as today (same op charges, same cursor resume). Result placements carry `dir`.
2. `logic/bp/search.lua`:
   - `candidate_links`: edge links get `flow_id = fid` and `ext = "in"` / `"out"` (block-to-block links unchanged).
   - `prepare_candidate`: when `Pack.mode == "sugiyama"` and `pack_layered(state)`: nodes = candidate blocks
     `{id = block.id or block.block_id, w, h, ports = {{port_id, role, attach_dx, attach_dy, kind}}}`;
     `state.work.draw = FlowDraw.begin{nodes, links = state.work.pack_links, input_edge, output_edge, restarts = 30,
     sweeps = 8, seed = 1}`; `set_phase(state, "draw")`. Otherwise today's code unchanged.
   - New phase `"draw"`: `run_stage(state, "draw", FlowDraw, budget)`; when done: for each Block with a port whose
     `kind == "fluid"`: `partner_dir[port_id]` = world direction (0/4/8/12) toward its partner (edge link: toward
     that edge; Block partner: earlier Layer -> toward `input_edge`, later -> away, same Layer -> along across axis by
     rank), `o = Orient.choose{block = block, catalog = state.work.input.catalog, turn = turn_of[id], partner_dir = ...}`,
     `nb = Groups.reorient(state.work.groups, block, o)`; nil keeps block. Replace blocks in a COPY of the candidate
     (`state.work.candidate` = copy with new `blocks` list; never mutate `groups.result`), rebuild `pack_links`, then
     `Pack.begin{... same as today ..., mode = "sugiyama", drawing = state.work.draw.result, input_edge = ...}` and
     `set_phase(state, "pack")`.
   - A drawn candidate rejected -> existing `layered_fallback` (MaxRects) path, unchanged.
   - `require "logic.bp.flow_draw"` and `require "logic.bp.orient"` at file top.
3. New `tests/test_pack_drawn.lua` (header: PD2-PD6 red on round-51-base): build `Pack.begin` inputs by hand
   (pattern `tests/test_pack_layered.lua`, `tests/test_pack_links.lua`); drawing tables written by hand.
   - PD1: `Pack.mode` "layered": LP1-LP3 inputs give the same placements as base (copy expected values from running
     base once; say so).
   - PD2: sugiyama, 3 Blocks in one Layer ranks 1,2,3, room: across-axis order follows ranks.
   - PD3: obstacle on rank-2 target: Block drifts, still placed; cost includes P for broken rank.
   - PD4: dummy tile free alternative exists: no Block covers dummy tile.
   - PD5: two Turns equal otherwise: preferred `turn_of` wins.
   - PD6: 1-op budget per step == one big budget (deep compare placements).
   - PD7: `input_edge` "top": Layer 2 Block placed below Layer 1 Block.
4. New `tests/test_search_draw_phase.lua` (header: SD1-SD3 red on round-51-base): pattern
   `tests/test_candidate_links.lua` / existing search tests for a small prepared input.
   - SD1: `Pack.mode = "sugiyama"`: search passes phase "draw" before "pack"; with skeleton modules result placements
     exist; 1-op budget steps finish.
   - SD2: edge links carry `flow_id` and `ext`.
   - SD3: `Pack.mode = "layered"`: phase "draw" never appears.
5. Keep green (one at a time, `timeout 90`): `test_pack`, `test_pack_layered`, `test_pack_links`,
   `test_pack_adjacent_producers`, `test_pack_budget`, `test_pack_ticks`, `test_pack_buffer`,
   `test_pack_zone_blockers`, `test_candidate_links`, `test_pack_drawn`, `test_search_draw_phase`,
   `test_no_item_names`, `test_no_runtime_require`, `test_locale_keys`.

## Files this lane owns

logic/bp/pack.lua, logic/bp/search.lua, tests/test_pack_drawn.lua, tests/test_search_draw_phase.lua,
docs/tasks/286_drawn_pack.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/286`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane286-tests", "command": "git diff --name-only round-51-base HEAD | grep -Ev '^(logic/bp/pack\\.lua|logic/bp/search\\.lua|tests/test_pack_drawn\\.lua|tests/test_search_draw_phase\\.lua|docs/tasks/286_drawn_pack\\.md)$' | ( ! grep . ) && for t in test_pack test_pack_layered test_pack_links test_pack_adjacent_producers test_pack_budget test_pack_ticks test_pack_buffer test_pack_zone_blockers test_candidate_links test_pack_drawn test_search_draw_phase test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane286-tests-ok", "expect_exit": 0, "expect_regex": "lane286-tests-ok", "timeout_s": 2400}
{"name": "lane286-fast", "command": "out=$( (timeout 120 lua5.2 tests/test_pack_drawn.lua; timeout 120 lua5.2 tests/test_search_draw_phase.lua) 2>&1); for c in PD1 PD2 PD3 PD4 PD5 PD6 PD7 SD1 SD2 SD3; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -c ' 0 failed' | grep -q '^2$' && echo lane286-ok", "expect_exit": 0, "expect_regex": "lane286-ok", "timeout_s": 300}
```

# bound: 5400s
