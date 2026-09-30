# 285b_flow_draw_slices: drawing really sliced, fast crossing count, crossings recounted by the test

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-285`, branch `lane/285`
(continue on top of your own commits), base tag `round-51-base`, merge target `int/r51`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tests/golden/generate.lua`, `tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet
or headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine` or `math.random`. `require` only at file
top level. **No game item or entity name in `logic/`.**

## Explain very simply

Your `logic/bp/flow_draw.lua` (task `docs/tasks/285_flow_draw.md`, read it again: contract and method stay) draws
right, but integrator review found (legalcopilot-dev 2026-09-30):

1. **Not sliced.** `FlowDraw.step` runs `build()` — every restart and sweep — inside the FIRST call, then only counts
   `state.progress` down. Measured: 12 Blocks, 72 links (210 dummies), `restarts=30, sweeps=8`, `step(state,
   {ops=2000})`: first call **11 332 ms**. The game runs one step per tick; the tick budget is 16 ms. This must be a
   real resumable state machine.
2. **Crossing count too slow.** `count_crossings` rebuilds both edge paths for every edge pair and compares every
   segment pair across ALL layers: O(E^2 * L^2) per call, 480 calls.
3. **Test trusts the code under test.** FD6 compares `r.crossings` (self-reported) with a baseline that skips long
   edges; the STEP 0 skeleton (crossings hard-coded 0) passes FD6. And the unconditional `print("FD1 ... FD7")`
   makes the label check pass even if cases vanish.
4. Restart shuffle `table.sort` comparator returns `out_at_end` for x pinned regardless of y: not a strict order
   when two pinned nodes meet (Lua may raise "invalid order function for sorting").

## What to build

1. `logic/bp/flow_draw.lua`:
   - `begin` stays cheap. Graph build (nodes, layers, dummies, segment lists) may be one phase; ordering work is a
     cursor over plain data only: `state.order[l]` = array of node indexes (numbers), `state.cursor = {phase,
     restart, sweep, layer, pass, i}`; no tables used as keys, no functions, no references between nodes in state
     (numbers and strings only) so checkpoints serialize it.
   - Every unit of work charges `budget.ops` (1 op per neighbour visited in barycenter, per segment pair compared in
     crossing count, per adjacent pair tried in transpose). `step` returns as soon as `budget.ops <= 0` and resumes
     exactly there next call. Result identical for any slicing (FD3 already asserts).
   - Crossings per adjacent layer pair l,l+1 from precomputed segment list `seg[l] = {{upper_index, lower_index}...}`
     (built once); count by sorting segments by upper rank then counting inversions of lower ranks (merge sort or
     O(s^2) on s segments of THAT layer pair only). Total = sum over layer pairs.
   - Comparator fix: pinned Outputs stay at their end by construction (remove them before sorting, re-append at the
     pinned end), never inside a comparator.
   - Three Outputs whose layers collide: keep moving until a free Layer end (loop, not one `+1`).
2. `tests/test_flow_draw.lua`:
   - Remove the unconditional label print; each case name carries its label (H.test name starts with it). The
     check greps the test output for PASS/FAIL lines as the harness prints them; if the harness prints nothing per
     passing case, print the label INSIDE each case body after its last assertion.
   - FD6: recount crossings in the TEST from the result alone (Blocks by `layer_of`/`rank_of`, Sources layer 0 by
     `rank`, Outputs by `layer`/`rank`, dummies by `link`/`layer`/`rank`; rebuild each edge's chain) and assert
     `recount == r.crossings` and `recount <= input-order recount` (same recount on the input order, dummies
     included). Must be red on the STEP 0 skeleton (`git show round-51-base:logic/bp/flow_draw.lua`).
   - FD8 (new): the 12-Block, 72-link graph above (build it in the test with the same LCG: nodes v1..v12, link a->b
     when `seed % 4 == 0` after `seed = (seed*1103515245+12345) % 2147483648`, seed start 12345, plus 6 Sources on
     v1..v6 and 1 Output on v12): `restarts=30, sweeps=8`, steps of `{ops=2000}`: every single `step` call under
     20 ms `os.clock()` and total under 3 s; result deep-equal to one `{ops=1e9}` run.
   - FD9 (new): two pinned Outputs meeting in a restart shuffle never raise (graph with 3 Outputs of one producer).
3. Keep green (one at a time, `timeout 90`): `test_flow_draw`, `test_no_item_names`, `test_no_runtime_require`,
   `test_locale_keys`.

## Files this lane owns

logic/bp/flow_draw.lua, tests/test_flow_draw.lua, docs/tasks/285_flow_draw.md, docs/tasks/285b_flow_draw_slices.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/285`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane285b-tests", "command": "git diff --name-only round-51-base HEAD | grep -Ev '^(logic/bp/flow_draw\\.lua|tests/test_flow_draw\\.lua|docs/tasks/285_flow_draw\\.md|docs/tasks/285b_flow_draw_slices\\.md)$' | ( ! grep . ) && for t in test_flow_draw test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane285b-tests-ok", "expect_exit": 0, "expect_regex": "lane285b-tests-ok", "timeout_s": 1200}
{"name": "lane285b-fast", "command": "out=$(timeout 120 lua5.2 tests/test_flow_draw.lua 2>&1); ! echo \"$out\" | grep -q 'FD1 FD2 FD3' || { echo UNCONDITIONAL-PRINT; exit 1; }; for c in FD1 FD2 FD3 FD4 FD5 FD6 FD7 FD8 FD9; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 9 passed, 0 failed' && echo lane285b-ok", "expect_exit": 0, "expect_regex": "lane285b-ok", "timeout_s": 300}
```

# bound: 3600s
