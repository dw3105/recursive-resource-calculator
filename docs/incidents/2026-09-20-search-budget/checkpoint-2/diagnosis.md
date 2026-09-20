# BP_FAIL_SEARCH_BUDGET — offline replay diagnosis

Host legalcopilot-dev, 2026-09-20. Plan checkpoint 3, step 1 ("Replay and diagnose, before changing policy").
Evidence class: **offline replay**. Not an in-game cause claim. Nothing here is fixed yet.

## Capture

Fresh export from the 1.1.53 diagnostic build, base 2.0.77, default configuration.

| Artefact | sha256 |
|---|---|
| `export.txt` | `ae2c3ae3256511ad41eb4b8b59473047bd147adfd4bfd3e7a4d08b37351d3237` |
| `prepared_input.json` | `015361d69ee6991f233593d9464815470a51c4bf756c0dd3200eee7a3d7274db` |

`options` carries no `search_budget`, `max_ops`, `max_search_grids` or `max_grid_trials`.

## Replay equivalence

`lua5.2 tests/golden/generate.lua --input prepared_input.json` on unchanged HEAD `e50f938` reproduces the
reported run exactly:

```json
{"errors":[{"code":"BP_FAIL_SEARCH_BUDGET"}],"ok":false,
 "progress":{"done_units":7,"phase":"failed","total_units":49},"stage":"failed"}
```

## Four defects, in the order the pipeline meets them

### D1 — beacon coverage tests the machine centre, not box overlap

`logic/bp/groups.lua:251-261` (`covers`) and `logic/bp/validate.lua:637` (`point_in_area`) ask whether the
machine **centre** sits inside the beacon supply area. `validate.lua:235-236` documents the engine rule as
collision-box overlap, implements it in `box_in_area` (`:238-241`), and uses it for poles at `:672`. Beacons use
the wrong one.

Measured: beacon row sits at `y=0 h=3` (centre y 1.5), supply distance 3, so the deepest reachable centre is
`y=4.5`; machines start at `y=3` and a 5x5 machine's centre is `y=5.5`.

```text
GEO beacon=7,0 3x3 supply=3x3 required=5 covered=0
GEOM machine=machine:casting-iron:1 0,3 5x5
covered=0 on 3744 of 3744 beacon placements
```

Every block gets `invalid_coverage` (`groups.lua:574`), `make_candidates` (`:657-697`) drops all of them,
`candidates=0` on all 49 grids, run dies at `done_units=7`.

### D2 — one beacon row cannot satisfy count >= 3

`build_block` places all `group.count` beacons in a single horizontal row at pitch `row.w + 1 = 4`
(`groups.lua:462-507`), then `:558-574` demands every machine be covered by all `group.count` of them. Three
supply rects 9 tiles wide, spaced 4 apart, intersect in about one tile.

Patching D1 to overlap semantics and re-running: `got` reaches 2 at most, **never 3**, across 2280 coverage
checks. Candidates stay 0.

```text
COVER step=casting-iron sig=beacon|normal|speed-module-3@normalx2|same_type need=3 got=2 beacons=3
distinct got: got=0 (24), got=1 (432), got=2 (1824), got=3 (0)
```

The captured sheet asks for 3 beacons per machine, so D2 blocks it on its own.

`validate.lua:660` requires `count_per_machine`; `groups.lua:574` compares against `group.count`
(`:367`, the max per-machine requirement in the block). Separate mismatch, noted, not the blocker here.

### D3 — roboport connection distance is absent and silently defaults to 1

The 2.0.77 capture's `catalog.robo` is exactly:

```json
{"construction_radius":55,"logistic_radius":25,"name":"roboport","quality":"normal","tile_h":4,"tile_w":4}
```

No `connection_distance`. `logic/catalog.lua:709` writes `connection_distance = entity.connection_distance`,
which was nil on the engine. `logic/bp/search.lua:189-190` falls back to `1`. `Grid.robo_grid`
(`logic/bp/grid.lua:255-271`) then builds `w = tile_w + (cols - 1) * spacing`, so the largest 8x8 grid is
**11 x 11 = 121 tiles**.

```text
FIT fits=false cols=8 rows=8 gw=11 gh=11 need=387 widest=11 tallest=10 blocks=5
30 candidates x 49 grids, fits=false every time
```

`candidate_fits_grid` (`search.lua:996-1013`) rejects them **silently** — no rejection record, no error.
`validate.lua:618-621` reads the same missing field with fallback 0.

With `connection_distance = 50` injected, 4 of 4 candidates fit and the search does 446785 units of real work
instead of 1477.

### D4 — three causes share one code, and the reasons are erased

`finish_search_budget` (`search.lua:927-929`) reports `BP_FAIL_SEARCH_BUDGET` for the ops cap (`:1046`, `:1054`,
`:1176`), the grid cap (`:965`) and the power bound (`:966`).

```text
DIAG budget max_ops=nil ops=nil gridhit=true powerhit=false incumbent=false
```

Grid-trial exhaustion, reported as a budget failure. `reason_details` never reaches the output: the emitted
record carries a bare `{"code":"BP_FAIL_NO_LAYOUT_GRID_LIMIT"}` and nothing else. `record_rejection` is called
only at `:1142`, so pack, route and power rejections are never recorded at all.

## What is behind them

With D1, D2 and D3 neutralised in a scratch worktree, the search reaches the route stage and fails there:

```text
REJECT phase=route codes=BP_R_NO_PATH
```

The failure lane 084 already saw. Its size is unknown.

## De-listed as this incident's cause

`derive_allowance` (`search.lua:912-920`) capping the job at 4x a **failed** candidate's cost is a real
implementation defect, reproduced earlier on HEAD 285158b. It is **not** what ended this run: `max_ops` was
never derived in any replay of this capture (`max_ops=nil` throughout). It stays on the repair list on its own
merits.

## Counterfactual ladder

| Change applied | candidates | done_units | result |
|---|---|---|---|
| none (unchanged HEAD) | 0 | 7 | `BP_FAIL_SEARCH_BUDGET` |
| D1 overlap | 0 | 7 | `BP_FAIL_SEARCH_BUDGET` |
| D1 + beacon count forced to 1 | 30 | 367 | `BP_FAIL_SEARCH_BUDGET` (gridhit) |
| D1 + count 1 + full 49-grid ladder | 30 | 1477 | `BP_FAIL_NO_LAYOUT_GRID_LIMIT` |
| D1 + count 1 + `connection_distance = 50` | 30 (4 fit) | 446785 | `BP_R_NO_PATH` in route |

Forcing the beacon count is a diagnostic counterfactual only. The captured configuration is never modified to
make a run pass.
