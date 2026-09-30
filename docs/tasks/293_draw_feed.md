# 293_draw_feed: drawn feed + apply: 8 real orients per Block in, drawn Turn + Flip applied, pack drawn dir hard, export

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-293`, branch `lane/293`,
base tag `round-53-base` (`9719cddfd95a00be2a432f1c01e9127d869d77e0`), merge target `int/r53`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tests/golden/generate.lua`, `tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, `tests/test_drawn_e2e.lua`, or
any full suite, whole sheet or headless run of any kind. No command may take more than 60 s.** Run only single test
files, one at a time, with `timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4) or
`timeout 90 python3 tests/<file>.py`; headless test files only offline: `timeout 90 lua5.2 tests/game/offline.lua
tests/game/<file>.lua`. Never use `coroutine` or `math.random`. `require` only at file top level. **No game item or
entity name in `logic/`.** Deterministic: fixed scan order, ties broken by id string. Every new test must FAIL on the
base code where this task says "red on base" (say so in its header comment, with date 2026-09-30); commit it red
first, then the code.

Read `CONTEXT.md` first: terms **Block**, **Flow graph**, **Source**, **Output**, **Layer**, **Turn**, **Flip**,
**Crossing**, **Port side**, **Material cost**, **Drawn pack**, **Layered pack**, **Fallback**.

## Frozen contract (never change these shapes)

```lua
-- Drawing input node (search.lua builds it; flow_draw.lua reads it). Old fields id, w, h, ports stay.
node.orients = {          -- key "turn|mirror": turn in {0,4,8,12} (Block Turn, clockwise, 4 = 90 deg), mirror in {0,1}
  ["4|1"] = {w = <int>, h = <int>, ports = {[port_id] = {side = 1|2|3|4, place = <0..1>, kind = "item"|"fluid"}}},
  ...                      -- a missing key = that orientation cannot be built; never an empty table
}                          -- side: 1 left, 2 top, 3 right, 4 bottom, in world frame AFTER the Turn;
                           -- place: position along that side, 0 = top/left end, 1 = bottom/right end (tile centre / length)
input.costs = {ug_pair = <n>, belt_tile = <n>, ptg_pair = <n>, pipe_tile = <n>}   -- Material cost units
                           -- absent or any field nil -> defaults {ug_pair=17.5, belt_tile=1.5, ptg_pair=15, pipe_tile=1}
-- Drawing result (flow_draw.lua fills; old fields layer_of, rank_of, layers, sources, outputs, dummies, crossings stay):
result.turn_of[id]   = 0|4|8|12      -- chosen Block Turn
result.mirror_of[id] = 0|1           -- chosen Flip
result.score         = <number>      -- Material cost of Crossings + port detours of the best drawing
result.ug_pred       = <int>         -- Crossings of the best drawing (each one = one predicted Underpass)
-- search r.json export: result.search.draw = {crossings=, score=, ug_pred=, dir_overrides=}
-- catalog field (plain data): catalog.material = {[entity_name] = <raw units per ONE entity>}
```

## Explain very simply

Drawn pack (`RRC_PACK=sugiyama`) draws the Flow graph (`logic/bp/flow_draw.lua`), then `logic/bp/search.lua` turns and
flips Blocks, then `logic/bp/pack.lua` places them. Player ruling (round 53 grill Q5): the DRAWING chooses each Block's
Turn and Flip from 8 real orientations; nothing turns or flips a Block after drawing. This lane feeds the drawing the
real orientations and applies its choice. The drawing module itself is not yours: code against the frozen contract
above (`node.orients` in, `turn_of` + `mirror_of` out). Layered pack (default) must stay byte-identical.

## Today (a1cd87b line numbers)

- `prepare_candidate` (`search.lua:1556-1582`) builds `nodes = {id, w, h, ports}` and calls `FlowDraw.begin`.
- Draw phase (`search.lua:1743-1807`): per Block computes `partner_dir`, calls `Orient.choose{turn = turn_of[id]}`
  (`orient.lua:12`), rebuilds via `Groups.reorient(state.work.groups, block, {dir, mirror})` (`groups.lua:2622`, cache
  `work.reorient_cache["id|dir|mirror"]`, `REORIENT_OPS = 2000` per miss, one Block per step), then `Pack.begin{mode =
  "sugiyama", drawing}`.
- Pack (`pack.lua:1029`) gives drawn Blocks `allowed_dirs = {0,4,8,12}`; `pack.lua:731-749` adds a soft penalty when
  `direction ~= drawing.turn_of[id]`.
- Two rotation levels exist: the pack's Block Turn (placement `dir`) and the machine `dir` inside a rebuilt Block.
  **Rule this round (drawn only): the machine dir inside the Block stays 0; the Block Turn does all rotating; only the
  Flip needs a rebuild.**

## What to build

1. **Orients before drawing.** In the drawn path, before `FlowDraw.begin`, add a sliced phase that, per Block in
   fixed order: variant m=0 = the Block as grouped; variant m=1 = `Groups.reorient(groups, block, {dir = 0, mirror =
   true})` ONLY for Blocks with a fluid port (Orient's rule: every machine `can_flip`); a nil rebuild = no m=1. Charge
   `REORIENT_OPS` per cache miss, 1 per hit, like today. For each variant and each Turn t in {0,4,8,12} derive
   `orients["t|m"]` from the variant's ports with the existing geometry (`Grid.rotate_size`, `Grid.place_port`,
   `grid.lua:177,255-263`): side of the Block the port's attach tile touches after the Turn, place = (offset along that
   side + 0.5) / side length. Pass `input.costs` from `catalog.material` (entities `catalog.belt.underground` pair = 2
   x cost, `catalog.belt.belt`, `catalog.pipe.underground` pair = 2 x cost, `catalog.pipe.pipe`); any missing -> leave
   that field nil (drawing defaults).
2. **Apply the drawing.** Replace the `Orient.choose` loop: per Block take `mirror_of[id]` (default 0) -> use variant
   m (already built, cached); Turn = `turn_of[id]` (default 0). No `partner_dir`, no `Orient.choose` in the drawn path
   (layered path never called it).
3. **Pack: drawn dir hard.** In `Pack.begin` mode `sugiyama`, `allowed_dirs = {turn_of[id]}` when present; if the
   Block fits nowhere with that dir, retry it once with `{0,4,8,12}` and count `state.counters.dir_overrides`
   (+1 per Block). Remove the soft `direction ~= preferred` penalty term. Layered/MaxRects paths untouched.
4. **Export.** In the search result next to `fell_back` (`search.lua:2030-2031`): `result.search.draw = {crossings,
   score, ug_pred, dir_overrides}` when a drawing was used, else absent.
5. **Verdict row.** `tools/sheet_verdict.sh` appends `pred_ug=<n|-> dir_overrides=<n|->` read from r.json
   `result.search.draw` (python inline, like `fell_back`). Keep every existing field and order.

## Tests (print code when each passes)

In `tests/test_search_draw_phase.lua`:
- SD5 orients: a drawn search on a hand-built candidate with one fluid Block and one item Block -> FlowDraw input
  node of the fluid Block has 8 keys, item Block 4 keys (`t|0` only); a port on the Block's west edge at key `0|0`
  has side 1 and at key `4|0` side 2 (red on base).
- SD6 apply: stub drawing result `turn_of = {X = 8}, mirror_of = {X = 1}` -> the Block handed to Pack is the mirror
  variant and Pack gets `allowed_dirs = {8}` (red on base).
- SD7 export: finished drawn search result has `search.draw.ug_pred` and `dir_overrides` numbers (red on base).
- SD8 no `Orient.choose` call in the drawn path (wrap it, count calls == 0) (red on base).
- SD1-SD4 kept.
In `tests/test_pack_drawn.lua`:
- PD8 drawn dir only; a Block that cannot fit in its drawn dir but fits turned -> placed, `dir_overrides == 1`
  (red on base). PD1-PD7 kept (PD5 asserted the soft preference: rewrite on purpose to the hard rule, comment cites
  grill Q5 2026-09-30).

## Files this lane owns

`logic/bp/search.lua`, `logic/bp/pack.lua`, `tools/sheet_verdict.sh`, `tests/test_search_draw_phase.lua`, `tests/test_pack_drawn.lua`, `docs/tasks/293_draw_feed.md`. Not `flow_draw.lua` (drawing module): code against the contract; `test_flow_draw` must stay green on your branch.

## Commit, THEN check

Commit on `lane/293`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane293-tests", "command": "git diff --name-only round-53-base HEAD | grep -Ev '^(logic/bp/search\\.lua|logic/bp/pack\\.lua|tools/sheet_verdict\\.sh|tests/test_search_draw_phase\\.lua|tests/test_pack_drawn\\.lua|docs/tasks/293_draw_feed\\.md)$' | ( ! grep . ) && for t in test_search_draw_phase test_pack_drawn test_pack test_pack_layered test_pack_links test_pack_ticks test_search test_search_pipeline test_search_strict test_orient test_flow_draw test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane293-tests-ok", "expect_exit": 0, "expect_regex": "lane293-tests-ok", "timeout_s": 3000}
{"name": "lane293-fast", "command": "out=$( (timeout 120 lua5.2 tests/test_search_draw_phase.lua; timeout 120 lua5.2 tests/test_pack_drawn.lua) 2>&1); for c in SD5 SD6 SD7 SD8 PD8; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -Eq 'FAILED|FAIL |[1-9][0-9]* failed' && { echo RED; exit 1; }; echo lane293-ok", "expect_exit": 0, "expect_regex": "lane293-ok", "timeout_s": 300}
```

# bound: 5400s
