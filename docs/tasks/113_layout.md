# 113 layout: measure the route, finish the artifact, and stay under five seconds

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-113`, branch `lane/113`, base tag `round-13-base` (resolve with `git rev-parse round-13-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 25, rules 25.4, 25.5. Baseline: `docs/round-13-baseline.md`.

`logic/bp/route.lua` never sets `segment.length`, and `logic/bp/validate.lua:1062` sums
`finite(segment.length, 0)`, so route cost read 0 while 270 transport entities stood on the grid.

`logic/bp/pack.lua:291` reserves a margin equal to the block's port count on every side. That bought routing
feasibility with a coarse reservation; it is not a compact layout.

Measured on the captured sheet, host legalcopilot-dev 2026-09-21, lua5.2:

```
candidate 1  grid 54x54  FAIL BP_R_NO_PATH fluid/molten-iron  325982 expansions  7.32s
candidate 2  grid 54x54  OK                                   160077 expansions  3.54s
TOTAL 13.49s, of which route 78%, power 12%, pack 4.5%
```

The two candidates differ ONLY in the order blocks enter packing. Three speed attempts were measured and all
three were worse: ordering the frontier by remaining distance never finished one candidate in 110s; disabling
the four direction-order retries saved 13%; granting a restart only while it buys progress took the run to
66.72s and 60 candidates, because those restarts are what make candidate 2 succeed. Do not repeat them.

`logic/bp/search.lua:1271` sets `state.ok = true` as soon as `Serialize` succeeds. `logic/bp/generation.lua`
then encodes, marks success and may deliver, with no reconciliation against the plan.

Reserved publication recognizes only `phase == "serialize"` (`search.lua:953`, `:1021`, `:1145`, `:1291`). At
an exhausted `max_ops` every other phase reaches `finish_search_budget`, which calls `begin_serialization`
when an incumbent exists.

PRESERVE: `logic/bp/validate.lua`, `logic/bp/plan.lua`, `logic/bp/groups.lua`, `logic/bp/serialize.lua`,
`logic/bp/generation.lua`, `logic/bp/geometry.lua`, `tests/harness.lua`,
`tests/test_blueprint_physical_contract.lua`, `docs/feature-contracts.md`, `tools/**`, `info.json`,
`mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/route.lua`, `logic/bp/pack.lua`, `logic/bp/search.lua`,
`tests/test_route.lua`, `tests/test_route_footprints.lua`, `tests/test_route_layout_contract.lua`,
`tests/test_pack.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua`,
`tests/test_search_allowance.lua`.

## What to build

**Measured length.** Every placed segment carries its measured length, including underground span, each
physical segment counted once, fluid detours included. Transport entity count stays a separate metric.

**Consume, never redefine.** Lane 111 publishes the metric keys and the comparator in `validate.lua`. Read
them. Never define a second schema, and never reintroduce `footprint_area` or `route_length`.

**Finalization is one reserved sequence.** Add a budgeted reconciliation phase AFTER serialization and BEFORE
terminal success, calling `Validate.reconcile_artifact`. Exploration exhaustion must never reset either phase
back to serialization. Both yield within the tick allowance. Cancellation and a revision change invalidate the
pending result throughout. Success is impossible until reconciliation completes. On mismatch: a named failure
and NO successful artifact.

**Trap.** Adding a `reconcile` branch naively lets `finish_search_budget` call `begin_serialization` again and
restart the sequence. A generic tiny-budget test does not necessarily reach that boundary. Write the case
against it: valid incumbent, exploration exhausted, serialization finished, reconciliation yielding, save and
reload, then finish WITHOUT restarting serialization. Repeat with an artifact mutation, with cancellation, and
with a revision change; each terminates with no delivery.

**Candidate order first.** The five-second ceiling is the user's hard requirement. Candidate order is the
first lever, because candidates 1 and 2 differ only in block order. Report the smallest failing case if the
ceiling cannot be met; never widen a search allowance to reach it.

**Corridors by traffic.** Size a corridor by the traffic and the legal connections on the side that needs it,
never by adding the port count to all four sides.

**Bounded improvement.** First feasible no longer ends the search. Keep the best validated incumbent under a
bounded improvement allowance, yield per tick, survive save and reload, and report whether improvement was
exhausted or cancelled.

**No ceilings here.** Layout work in this lane is correctness and measurement only. Acceptance ceilings come
from an engine-verified reference in a later stage.

## Case names this lane must use

In `tests/test_route.lua`:

- `RT1` a nonempty transport path measures a NONZERO cost, against an independently derived expectation, with
  underground span included and each physical segment counted once;
- `RT2` a fluid detour is included in the cost and never silently omitted.

In `tests/test_search_budget.lua`, the exhausted-budget boundary, all four:

- `FN1` valid incumbent, exploration exhausted, serialization finished, reconciliation yields, save and
  reload, then finishes WITHOUT restarting serialization;
- `FN2` the same with an artifact mutation: terminates with NO delivery;
- `FN3` the same with cancellation: terminates with NO delivery;
- `FN4` the same with a revision change: the pending result is invalidated.

A generic tiny-budget test does not reach that boundary. `search.lua:953`, `:1021`, `:1145` and `:1291`
recognize only `phase == "serialize"`, so a naive reconcile branch lets `finish_search_budget` call
`begin_serialization` again.

## What done mean

```checks
{"name": "red-proof", "command": "sh tools/lane_rows.sh tests/test_route.lua --min-cases 4 --pass RT1 || exit 1; S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; sh tools/lane_mutate.sh $S segment-length-zero >/dev/null 2>&1 || rc=1; (cd $S && sh tools/lane_rows.sh tests/test_route.lua --min-cases 4 --fail RT1) >/dev/null 2>&1 || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "rows", "command": "sh tools/lane_rows.sh tests/test_route.lua --min-cases 4 --pass RT1,RT2", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "finalization-rows", "command": "sh tools/lane_rows.sh tests/test_search_budget.lua --min-cases 4 --pass FN1,FN2,FN3,FN4", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "five-second-ceiling", "command": "start=$(date +%s%N); out=$(timeout 120 lua5.2 tests/golden/generate.lua tests/golden/cases/player-am2-chain/prepared_input.json 2>&1); rc=$?; end=$(date +%s%N); ms=$(( (end - start) / 1000000 )); [ $rc -eq 0 ] || { echo generator-aborted; exit 1; }; printf %s \"$out\" | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)\" || { echo the-generator-did-not-deliver; exit 1; }; [ $ms -lt 5000 ] || { echo took ${ms}ms against the 5000ms ceiling; exit 1; }; echo ceiling-met ${ms}ms", "expect_exit": 0, "expect_regex": "ceiling-met", "timeout_s": 600}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 113_layout", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-13-base --manifest docs/tasks/113.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 3600s
