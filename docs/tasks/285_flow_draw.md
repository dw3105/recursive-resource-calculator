# 285_flow_draw: draw the Flow graph with fewest Crossings before pack

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-285`, branch `lane/285`,
base tag `round-51-base`, merge target `int/r51`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

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

Read `CONTEXT.md` section "Layout" first (Block, Flow graph, Source, Output, Layer, Turn, Crossing).

Packer today places Blocks one by one; nobody looks at whole picture, so belts cross. New flagged mode draws the
Flow graph first with textbook layered drawing (Sugiyama), then packer aims each Block at its drawn spot. This lane
writes the drawing only. Method: `~/share/RRC/layered-crossing-minimization.md` (read sections 4-7). Graphs are tiny:
4-12 Blocks per real sheet (measured 2026-09-30), so simple O(m'^2) crossing count is fine.

`logic/bp/flow_draw.lua` holds a frozen contract (top comment) and a skeleton body. Keep every signature and every
result field exactly; replace the body.

Input `links` come from `search.lua` `candidate_links`: `{a = {block_id, port_id}, b = {block_id, port_id}}` is one
flow from producer Block `a` to consumer Block `b`. Edge links: `{a = {block_id, port_id}, b = {edge = "left"|...},
flow_id = F, ext = "in"}` means Block `a` consumes external input F; `ext = "out"` means Block `a` produces external
output F. Several links may share one `flow_id`: one Source (or Output) per `flow_id`.

## What to build

1. `logic/bp/flow_draw.lua` body:
   - Nodes: one per Block; one Source per distinct `ext = "in"` `flow_id`; one Output per distinct `ext = "out"`
     `flow_id`. Edges: Block->Block links, Source->Block, Block->Output. Duplicate (a, b) pairs count once.
   - Layers: Sources layer 0; Block layer = 1 + max layer of its producers (longest path). Cycle among Blocks: stop
     layering after #nodes passes and keep what exists (preflight refuses cycles already; never loop forever).
   - Output layer = producer layer + 1 (producer = first Block by input order producing it). An Output joins that
     Layer and is pinned to its output-edge end: last rank for `output_edge` in {"bottom", "right"}, first rank for
     {"top", "left"}. Pinned nodes never move in sweeps. Two Outputs pinned to one Layer end: the second moves to the
     next Layer (one more Layer after its producer) — no two Sources/Outputs share a border spot.
   - Dummy nodes: an edge spanning k > 1 Layers gets k-1 dummies, one per Layer between.
   - Crossing count between adjacent Layers: pairs `(pos[a1]-pos[a2])*(pos[b1]-pos[b2]) < 0`; every crossing counts
     1 (no weights).
   - Order: start = input order (Blocks in `nodes` order, Sources by first appearance, dummies after their edge
     tail's position). Per restart r = 1..restarts: r == 1 start order, else deterministic shuffle of each Layer
     (LCG seeded from `seed` and r; pinned Outputs stay pinned). Per sweep i = 1..sweeps: barycenter down sweep
     (key = mean position of neighbours in Layer above; no neighbours keep position; ties by current position),
     transpose, up sweep (neighbours below), transpose. Keep best total crossings; ties keep earlier.
   - Transpose: swap adjacent pair when crossings(v,u) < crossings(u,v) over both neighbouring Layers; at most 10
     passes; never swap a pinned node.
   - `turn_of[id]` (Block Turn preferred): ports carry `attach_dx/attach_dy` in Block frame, side from attach:
     `x == -1` left, `x == w` right, `y == -1` top, `y == h` bottom. Turn t in {0,4,8,12} (clockwise quarter turns,
     same as `logic/bp/grid.lua` `rotate_dir`) rotates each side clockwise t/4 times. Choose t making most `in` ports
     face the input edge side and most `out` ports face away from it (score = in ports facing input edge + out ports
     facing opposite edge); ties -> smallest t.
   - Slicing: `step(state, budget)` spends ops (1 op per edge pair checked is fine) and returns false until done;
     state holds only plain data (numbers, strings, tables; no functions) so checkpoints can save it. The result is
     the same for any budget sizes.
   - Result fields exactly as the contract: `layer_of` / `rank_of` for Blocks (Layer and 1-based rank within Layer
     counting every node incl. Sources/Outputs/dummies), `layers` (Block ids only, by rank), `sources`, `outputs`,
     `dummies` (`link` = index into input `links`), `crossings`, `turn_of`.
2. New `tests/test_flow_draw.lua` (header: FD1-FD7 red on round-51-base except FD5):
   - FD1: 3-Block chain + 1 Source + 1 Output -> crossings 0, layers 1,2,3, Output layer 4.
   - FD2: K2,2-plus graph whose optimum is 1 crossing (build one where input order gives >= 2) -> crossings 1.
   - FD3: same result table (deep compare) for budget 1 op per call vs 1e9 ops, on a 12-Block graph.
   - FD4: two Outputs from one producer: different Layers or ranks, each at output-edge end; `output_edge` "top".
   - FD5: each of 4 `input_edge` values: layer of consumer > layer of producer for every Block link.
   - FD6: 20-Block deterministic pseudo-random DAG (fixed LCG in test): crossings <= crossings of input order.
   - FD7: Block w=3 h=2, 2 `in` ports on top side (attach_dy = -1), 1 `out` port bottom (attach_dy = 2). Expected
     `turn_of`: input_edge left -> 12, top -> 0, right -> 4, bottom -> 8 (clockwise quarter turns: top side becomes
     right at turn 4). Assert all four.
3. Keep green (one at a time, `timeout 90`): `test_flow_draw`, `test_no_item_names`, `test_no_runtime_require`,
   `test_locale_keys`.

## Files this lane owns

logic/bp/flow_draw.lua, tests/test_flow_draw.lua, docs/tasks/285_flow_draw.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/285`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane285-tests", "command": "git diff --name-only round-51-base HEAD | grep -Ev '^(logic/bp/flow_draw\\.lua|tests/test_flow_draw\\.lua|docs/tasks/285_flow_draw\\.md)$' | ( ! grep . ) && for t in test_flow_draw test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane285-tests-ok", "expect_exit": 0, "expect_regex": "lane285-tests-ok", "timeout_s": 1200}
{"name": "lane285-fast", "command": "out=$(timeout 120 lua5.2 tests/test_flow_draw.lua 2>&1); for c in FD1 FD2 FD3 FD4 FD5 FD6 FD7; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane285-ok", "expect_exit": 0, "expect_regex": "lane285-ok", "timeout_s": 300}
```

# bound: 3600s
