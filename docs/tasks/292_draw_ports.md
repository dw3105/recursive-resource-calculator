# 292_draw_ports: drawing sees real ports: Source edges, ops left, port-to-port Crossings, Turn+Flip by Material cost

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-292`, branch `lane/292`,
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

`logic/bp/flow_draw.lua` draws the Flow graph before packing. Today it sees each Block as a dot: a flow line runs
from dot to dot, so the drawing does not know that a belt must leave from a real port on a real side of the Block.
Measured 2026-09-30 on green-science-1s: drawing counts 0 Crossings, router builds 14 Underpasses. Player ruling
(round 53 grill): every flow runs Port side to Port side; the drawing chooses each Block's Turn AND Flip itself (from
`node.orients`), scoring by Material cost (`input.costs`); lowest score wins.

## Bugs to fix first (each with its red test)

1. **Source edges never drawn** (`flow_draw.lua:42-52`). An external input link is `{a = <consumer port>, b = {edge =
   "left"}, flow_id = F, ext = "in"}` (see `search.lua:1548-1549`: `a` is the CONSUMER, `b` has no block_id). Today
   `id_index[l.b.block_id]` is nil and `add_edge` silently skips, so a Source has no edges. Fix: link ext-in to the
   Source node of `flow_id` (edge Source -> consumer). Same care for ext-out (`a` = producer, edge producer -> Output).
   Test FD10 (red on base): 1 Block, 1 ext-in link, 1 ext-out link -> `#g.edges == 2` (read through
   `FlowDraw._test` or a new `FlowDraw._test.prepare(input)` export) and Source rank moves with its consumer.
2. **Ops returned inverted** (`flow_draw.lua:289`): `budget.ops = max(0, budget.ops - allowance)` stores ops SPENT
   where the caller (`search.lua:1228-1238` `run_stage`) expects ops LEFT. Fix: leave `budget.ops = allowance`
   (what is left). Test FD11 (red on base): step with `{ops = 5000}` on a tiny graph that finishes after spending < 50
   ops -> returned `budget.ops >= 4950`.

## What to build

3. **Port identity.** Edges keep both port ids (today deduped by node pair at `:37`): key an edge by
   `a_node|a_port|b_node|b_port`. Dummy chains keep the port of their real end.
4. **Endpoint model.** A node takes rank slot `[rank, rank + 1)` in its Layer. For the edge end at port p of node n in
   orientation o = `node.orients[key]`, with `s = o.ports[p].side` and `q = o.ports[p].place`:
   - side facing the partner's Layer (towards higher Layer for an out edge, lower for in): endpoint `rank + q`, detour 0;
   - side parallel to the Layers: endpoint at the slot edge nearer that side, detour = half the Block length along the
     Layer axis (tiles, from `o.w`/`o.h`);
   - side facing away: endpoint `rank + q`, detour = Block length along the Layer axis + its width across.
   "Facing the partner Layer" uses `input_edge`: Layers grow away from `input_edge` (left -> Layers grow to the right,
   so side 3 faces higher Layers, side 1 lower; top -> side 4 faces higher, side 2 lower; right/bottom mirror).
   Sources/Outputs/dummies are points: endpoint `rank + 0.5`, detour 0. A node with no `orients` is a point too
   (old behaviour).
5. **Crossings from endpoints.** Two segments between Layers L and L+1 cross when their endpoint orders differ
   (`(x1 - x2) * (y1 - y2) < 0` on the real endpoints, not ranks). Shared endpoints never cross.
6. **Score** = sum over crossings of cost(pair) + sum over edge ends of detour x cost(tile), where cost uses the edge's
   kind: fluid (either end port `kind == "fluid"`) -> `ptg_pair` / `pipe_tile`, else `ug_pair` / `belt_tile`; costs from
   `input.costs` with the defaults above. `result.score` = score of the best drawing, `result.ug_pred` = its
   crossings. Best drawing = lowest score (ties: fewer crossings, then first found). `result.crossings` = crossings of
   that best drawing (kept for old readers).
7. **Orient phase.** Delete the vote (`choose_turn`, `:8-24`, `:32`). Start each node at the first present key in
   order `0|0,4|0,8|0,12|0,0|1,4|1,8|1,12|1`. After every transpose pass add phase `orient`: for each block node in
   fixed order, try every present key, keep one only if the drawing's score gets strictly lower; 1 op per edge end
   re-scored; resumable mid-node (state plain data). `result.turn_of[id]` / `result.mirror_of[id]` from the best
   drawing's keys (turn = number before `|`, mirror = after).
8. **Keep** FD1-FD9 green. FD7 asserts the old vote (`turn_of` 12/0/4/8 per input edge): rewrite it on purpose to the
   new rule (a Block whose in-port sits on side 1 and out-port on side 3 at key `0|0`, input edge left -> keeps `0|0`
   because any other key adds detour); header comment cites player grill Q5 2026-09-30. FD8 bar (<= 20 ms per
   2000-op step; sliced == full) must hold with orients on the FD8 graph (give its nodes 8 orients each).

## Tests (tests/test_flow_draw.lua, print code when each passes)

- FD10 Source/Output edges drawn (red on base).
- FD11 ops left returned (red on base).
- FD12 port place: two Blocks in Layer 2 fed from one Block in Layer 1 through ports at place 0.9 and 0.1 -> the order
  that avoids the crossing wins; same graph with midpoints (no orients) counts it differently (red on base).
- FD13 wrong side: in-port on the side facing away -> `score` includes detour x `belt_tile`; with an orient key that
  puts it on the facing side present, the drawing picks that key (red on base).
- FD14 Flip: a Block whose `0|1` orient removes one Crossing vs `0|0` -> `mirror_of[id] == 1` (red on base).
- FD15 costs: fluid edge crossing costs `ptg_pair`; custom `input.costs` changes `score` exactly (red on base).
- FD8 kept (timing with orients).

## Files this lane owns

`logic/bp/flow_draw.lua`, `tests/test_flow_draw.lua`, `docs/tasks/292_draw_ports.md`. Only `flow_draw.lua` and its test. `search.lua` builds `node.orients` and applies the result; not yours.

## Commit, THEN check

Commit on `lane/292`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane292-tests", "command": "git diff --name-only round-53-base HEAD | grep -Ev '^(logic/bp/flow_draw\\.lua|tests/test_flow_draw\\.lua|docs/tasks/292_draw_ports\\.md)$' | ( ! grep . ) && for t in test_flow_draw test_pack_drawn test_orient test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane292-tests-ok", "expect_exit": 0, "expect_regex": "lane292-tests-ok", "timeout_s": 3000}
{"name": "lane292-fast", "command": "out=$( (timeout 120 lua5.2 tests/test_flow_draw.lua) 2>&1); for c in FD8 FD10 FD11 FD12 FD13 FD14 FD15; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -Eq 'FAILED|FAIL |[1-9][0-9]* failed' && { echo RED; exit 1; }; echo lane292-ok", "expect_exit": 0, "expect_regex": "lane292-ok", "timeout_s": 300}
```

# bound: 5400s
