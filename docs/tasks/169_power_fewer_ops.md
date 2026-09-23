# 169 power: pole placement in far fewer ops

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-169`, branch
`lane/169`, base tag `round-23-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch. Everything you need is on
`round-23-base`.

## You have about 35 minutes — do NOT stop early

**Do not end your turn until every item under "What to build" exists, is committed, and both checks have
run.** Stopping with uncommitted work is a failed lane. If one item is truly blocked, commit everything
else, then say which item and why.

## Explain very simply

The player clicked "generate" in Factorio 2.0.77 on 2026-09-23. After 10 minutes it was still
calculating and the game ran at 3 UPS the whole time. The game advances a blueprint search once per tick
with a budget of 2000 ops (`Jobs.OPS_PER_TICK`, `logic/jobs.lua`). A tick must stay short (a frame is
16.7 ms). Some steps do seconds of work inside ONE call and never give the tick back.

`tools/speed_probe.sh` replays the player's sheet exactly as the game does (2000 ops per `Search.step`) and
times every `begin`/`step` of each `logic/bp` module. `tools/speed_gate.sh` turns its output into a
pass/fail line. Measured at `round-23-base` on legalcopilot-dev 2026-09-23, `CAP=40`:

```
pack.step     worst 8.157 s   (4 calls, 18.3 s)
route.begin   worst 1.340 s   (4 calls, 4.2 s)
route.step    worst 0.783 s   (25 calls, 6.6 s)
groups.begin  worst 0.611 s
power.step    416 calls per power.begin (about 830k ops per candidate), worst 0.016 s
```

The rule for every module: **one op costs a few microseconds**, so 2000 ops fit in about 20 ms. A long
loop checks the budget and returns; the next call resumes from a cursor stored on the state.

The result must not change. `tests/fixtures/blueprints/round22_v5.txt` is the player's accepted blueprint
(v5, 242 entities, placed in game 2026-09-23).

## Where the code is

`logic/bp/power.lua`, `Power.step`: a phase machine (`candidate_position`, `candidate_occupied`,
`candidate_coverage`, `candidate_commit`, `greedy`, `connect`, `repair`, `prune*`, `publish*`). Each phase
spends one op per tiny unit (`consume`). On the player's sheet one candidate needs **416 calls of 2000 ops,
about 830k ops**, which is fine per tick (worst 0.016 s) but costs about 7 s of wall time per layout in
game at 60 UPS, and about 2 s CPU. The candidate sweep visits every grid position for every pole spec.

## What to build

1. **Measure first**: ops per phase on the player's sheet (temporary counters, not committed). Put the
   table in your commit message.
2. **Cut the work, not the accounting.** Skip positions that cannot matter (for example: only positions
   whose supply area touches an uncovered consumer, found from an index of consumer rects; occupied cells
   from a cell set, not a list walk). Keep one op ≈ a few microseconds, so a 2000-op call stays under
   20 ms. The chosen poles and wires on the player's sheet must stay as good: same or fewer poles, all
   consumers covered, one connected network.
3. `tests/test_power_ops.lua` (new), each row **red at `round-23-base`**:
   - **PO1** on a fixture shaped like the player's sheet (build it from a small consumer list), total ops
     to `done` fall below a named bound you measure (at least 5x below base).
   - **PO2** `{ops = 1}` per call and `{ops = 10^9}` give identical poles and wires.
4. Report `CAP=60 sh tools/speed_probe.sh` before and after, and the final product line.

## Traps

- **Determinism.** Same input, same layout: `tests/test_route_budget.lua`, `coord_key`. A cursor that
  resumes must visit exactly the same things in exactly the same order as the one-shot loop did.
- **Every budget size gives the same answer.** Run your module's tests with a budget of 1 op and of a huge
  budget; results must be identical.
- **Measure with the probe, not the full product.** `CAP=40 sh tools/speed_probe.sh` takes about 40 s;
  `sh tools/round21_product.sh` takes about 200 s — run it once, at the end, alone. Never run two long
  commands at the same time (the host wedged 2026-09-23 when two ran together).
- **Never touch** `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except
  this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/power.lua`, `tests/test_power_ops.lua`

## Commit, THEN check

Commit on `lane/169` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "power-regress", "command": "git diff --name-only round-23-base HEAD | grep -v '^docs/tasks/169' | grep -Ev '^(logic/bp/power\\.lua|tests/test_power_ops\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_power_ops.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo power-regress-ok", "expect_exit": 0, "expect_regex": "power-regress-ok", "timeout_s": 1800}
{"name": "power-speed", "command": "CAP=60 sh tools/speed_probe.sh > /tmp/rrc169-speed.txt; cat /tmp/rrc169-speed.txt; sh tools/speed_gate.sh ratio power.step power.begin 80 < /tmp/rrc169-speed.txt && sh tools/speed_gate.sh worst power.step 0.03 < /tmp/rrc169-speed.txt && sh tools/round21_product.sh > /tmp/rrc169-product.txt 2>&1; cat /tmp/rrc169-product.txt; grep -q '^product-ok$' /tmp/rrc169-product.txt && awk '/^ok=True entities=/{split($2,a,\"=\"); exit !(a[2] <= 242)}' /tmp/rrc169-product.txt && echo power-speed-ok", "expect_exit": 0, "expect_regex": "power-speed-ok", "timeout_s": 1500}
```

# bound: 2400s
