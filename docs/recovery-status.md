# Round 8 board — one list, replaces every older "next step"

Updated 2026-09-19 11:55 UTC, HEAD 5ac8dcc, by the integrator on host `legalcopilot-dev`. Branch
`feat/round-8-blueprints`, never pushed, never merged to `main`. Dispatch follows
`~/codex-reviews/rrc-parallel-execution-unblock-plan-2026-09-19-1014.md`: five disjoint lanes run beside every
physical repair, and no lane waits on the blueprint pipeline for work it can finish alone.

## Streams

| Stream | Lane | Owner live? | Base SHA | Owns | State and next command |
|---|---|---|---|---|---|
| Repair: block port binding | 047 | no | binding-base 835a66e | `logic/bp/groups.lua`, `logic/bp/route.lua`, `tests/test_groups.lua`, `tests/test_route.lua` | **merged** 93fcfe3 |
| S service lifecycle and capture | 048 | no | unblock-base 93fcfe3 | `gui/blueprint_dialog.lua`, `logic/bp/generation.lua`, `logic/engine_test_api.lua`, two new test files, `tests/test_bp_settings.lua` | **merged**; 20 lifecycle cases green, real-sheet gate red on purpose |
| Repair: perimeter port collision | 053 | no | collision-base d412c38 | `logic/bp/search.lua`, `tests/test_search.lua` | **merged**; the real-sheet gate is green |
| D dispatch preflight | 054 | **yes** | queue-base 29c5aa9 | `tools/lane_ownership.py`, new `tools/check_dispatch.py`, their tests | running |
| A API coverage | 055 | **yes** | queue-base 29c5aa9 | `tools/extract_api.py`, `docs/api/*.members.json`, `tests/test_api_shapes.lua`, new companion shapes test | running |
| L generation reload | 056 | **yes** | queue-base 29c5aa9 | `logic/bp/generation.lua`, `logic/engine_test_api.lua`, its test, two new tests | running |
| F capture case setup | 057 | **yes** | queue-base 29c5aa9 | new `tests/golden/capture_case.lua`, `tests/golden/setup/`, new `tests/test_case_capture.lua`, `docs/golden-case-authoring.md` | running |
| C calculation result record | 049 | no | unblock-base 93fcfe3 | `logic/calc_pipeline.lua`, `logic/calculation_result.lua`, their two test files | **merged**; wired into `control.lua` by the integrator |
| E real engine adapter | 050 | no | unblock-base 93fcfe3 | `tests/golden/engine/mod/`, `tests/test_engine_scenario.lua`, `tests/test_engine_runtime_adapter.lua`, `docs/engine-evidence/runner.md` | **merged**; 16 adapter cases drive the shipped adapter |
| R evidence contract and release gate | 051 | no | unblock-base 93fcfe3 | `tools/release_gate.py`, its tests, new `tests/tools/test_evidence_contract.py`, `docs/release-preparation.md` | **merged**; verdict FAIL was my broken manifest, verified by hand |
| G capture to case workflow | 052 | no | unblock-base 93fcfe3 | `logic/export_payload.lua`, its test, `tests/golden/add_case`, `tests/golden/lib/common.py`, `tests/tools/test_capture_workflow.py`, `docs/golden-workflow.md` | **merged**; a failed search still yields a draft |
| Lane 039 (superseded) | 039 | no | recovery-base-039c 7e4a5c2 | — | attempt 3 terminal; work preserved as checkpoint 3698214, now lane 048's first commit |
| Merged earlier | 037, 038, 040–046 | no | — | calculation activation, export shape, engine runner, release gate, golden workflow, coverage, two repairs | **merged** |
| Integrator | — | yes | — | `tests/harness.lua`, `tests/run.sh`, `control.lua`, `gui/sheet.lua`, `gui/export_dialog.lua`, locale, `docs/feature-contracts.md`, `docs/engine-evidence/examples/`, task files, corpus matrix, merges | active |

## Frozen interfaces (2026-09-19)

`docs/feature-contracts.md` §19 calculation result record, §20 prepared capture, §21 observation v1 with the
producer's own spelling. `docs/engine-evidence/examples/` holds one synthetic example per outcome kind.

## What is done

Waves 1 to 4 merged and sealed: snapshot, jobs, catalog, grid, export dialog, progress panel, payload, solver
steps, reset, report steps, plan, preflight, calc pipeline, settings, pack, groups, route, power, validate,
serialize, search, delivery, golden skeleton. Suite 2768 case runs, 0 failed, both interpreters, plus 27 Python
tooling tests and the golden corpus. Mutation batches: W1 8 of 9 with one recorded equivalent, W2 7 of 7,
W3 12 of 12, W3b 6 of 6, W4 6 of 6.

In game, on 2.0.77: the user confirms the debug export window works at 1.1.47 — selectable text that refuses
typing, Esc and the close key shut it, the title bar's X shuts it. Reset works, the blueprint dialog and its
per-category pickers are accepted. Two window defects reached the game first: `add{}` silently dropped
`read_only`, and an invented style name (`draggable_space_with_no_left_margin`) crashed on open. Both classes now
fail offline — `docs/api/2.0.77.styles.json` pins 582 core style names.

## Generate delivers, offline (2026-09-19 11:55 UTC)

`tests/test_blueprint_pipeline.lua` is 22 of 22, the mandatory real-sheet case included: a real calculated sheet
runs through the real modules to a delivered blueprint, with no stubbed Search and no precomputed plan. Whole
suite 2768 case runs, 0 failed, plus 70 Python tests. Test zips 1.1.47 and 1.1.48 built from `5ac8dcc`.
In game this is untested; the player's click is the next evidence.

## Four real defects found by running a real sheet

Both came from lane 039's end-to-end case, never from a unit test.

1. **Obstacle shape** (fixed, lane 043): `search.lua` gave `Pack.begin` the `{rect, owner}` records the power
   stage wants; the packer reads bare rectangles, so `Grid.free_regions` raised
   `logic/bp/grid.lua:73: attempt to compare number with nil`.
2. **Perimeter ports** (fixed, lane 044): `search.lua:314` asked `Grid.edge_slots` for slots on the grid's own
   envelope, and §5.8 puts an attach tile outside the envelope, which for the grid is outside the world.
   `route.lua:260` maps every outside cell to `"__outside__"` and routing treats it as blocked, so a real sheet
   ended `BP_R_PORT_BLOCKED`, then `BP_FAIL_NO_LAYOUT_GRID_LIMIT`. Contract §18 decided the rule; the search now
   builds perimeter slots on the grid's own edge cell, and a small real plan reaches `state.ok == true` with a
   serialized result.

Expect more of these. A unit-green module set says nothing about the path a player takes.

## What is not done

- Generate queues a real job and reaches routing. Three real defects are fixed (obstacle shape 043, perimeter
  ports 044, block port binding 047). No blueprint has reached a player yet; lane 048 owns that gate.
- One case in the matrix is accepted; 19 are drafts, every GOLD-09 category has a row, and `sh tests/golden/run
  --branch 2.0 --drafts report` names every gap and exits 1. `--branch 2.1` matches zero accepted cases.
- Every draft's capture-dependent fields are empty and its reason codes are terminal, checked by
  `tests/tools/test_golden_matrix.py` against the groups in `logic/bp/reason_codes.lua` (54 Python tests).
  Nothing is captured yet: a capture needs the real preparation path, which is lane 039's deliverable.
- Engine evidence: none, on either branch. 2.1 has no runtime here at all.

## Tag rule, learned the hard way

A lane's base tag is frozen the moment a worktree forks it. Repointing `recovery-base` after lanes 039 to 042
had forked it made `tools/lane_ownership.py` report `HEAD does not descend from the lane base`, and lane 042 took
a FAIL for work that was entirely inside its own five files. Every new dispatch gets its **own** tag, named for
that dispatch, and no tag is ever moved.

## Rules that still bind

One file has one owner. A lane never edits a locale file, `tests/harness.lua`, `tests/run.sh` or
`docs/feature-contracts.md`. The integrator merges with `git merge --no-ff` and runs the suite; `lane merge` is
not used, so its reviewer and verifier requirements do not apply. Nothing reaches `main` without the user's word.

## Known gap in the pinned API (2026-09-19, integrator)

Lane 050 reports `docs/api/2.0.77.members.json` and `docs/api/2.1.19.members.json` carry no `LuaEntity`, no
`LuaFluidBox` and no `LuaGameScript.write_file`, so `tests/test_api_shapes.lua` checks nothing about the members
the companion mod calls on those classes. Extending the pin is integrator work and is not done yet.

## Every verdict of this dispatch read FAIL for one reason: my manifests

`docs/tasks/04*.manifest` and `docs/tasks/05*.manifest` were written with literal backslash-n bytes, so
`tools/lane_ownership.py` read each as a single path and refused every changed file. Four lanes did their work
correctly and reported the cause precisely. Each was audited by hand against the repaired manifest before merge.

## Defect 4, found 2026-09-19 by probing the merged tree

Both perimeter ports stood on cell `(0, 0)`:

```text
perimeter in:item/raw  role=in  x=0 y=0
perimeter out:item/gear role=out x=0 y=0
```

`logic/bp/search.lua:343-354` takes slot 1 of each edge, and `logic/bp/settings.lua:14-15` makes the default
edges `left` and `top`, whose first slots are the same corner. One cell carries one belt, so routing reported
`BP_R_PORT_BLOCKED`. Every default sheet hits it. Lane 053 owns the fix.

## Routing, 2026-09-19 (integrator, host legalcopilot-dev)

`docs/tasks/058_reproducer.lua` reduces the player's sheet to five steps with beacon sharing, a fluid input,
external items and machine identifiers without quality. It is the gate for every routing repair. Merged
`lane/059` (`git merge --no-ff`, `0bba0db`) and then fixed three defects it exposed:

1. **A port lost the tile it is reached from.** Routing one demand laid a belt across the approach tile of a
   port it does not serve, and that port then had no path at all. Every port now claims its own tile and its
   approach tile before any demand is routed (`reserve_port_cells`). A belt already carrying the same flow may
   still pass, so one trunk feeding two consumers of one item stays legal (`tests/test_route.lua` R17).
2. **Two belts could not cross.** When the next tile in a direction is taken, the search dives under it and
   surfaces on the first free tile within the family's underground distance; the tiles between keep no segment.
   A tile the search can walk is never dived under (`tests/test_route.lua` R16).
3. **Order decided the outcome and nothing reordered.** Brute force over the fixture's first candidate: of the
   5040 demand orders, 5035 fail and 5 succeed. A failed demand now rips every segment out and routes again
   with itself first, each demand claiming the front once.

Also corrected: the two ends of an underground pair. Items go down at the demand's source, and a blueprint
spells that end `type = "input"`. The old spelling inverted every pair a generated blueprint would contain.
No engine run has confirmed this; it is reasoning from the blueprint format, and the engine tier settles it.

**Open, measured here, not fixed:** the smallest grid the search tries is one roboport block, 54x54 tiles, for
blocks that occupy about 130 tiles. Every path search is a breadth-first sweep of up to 2916 cells, and a failed
demand sweeps it four times, once per direction order. `Jobs.OPS_PER_TICK = 2000` then buys very little progress
per tick. The fixture reaches `stage=route` and keeps working; it has not yet printed `REPRO state=success`.


## Board, rebuilt from terminal records, host legalcopilot-dev, 2026-09-19 18:5x UTC

Every earlier "running" label in this file is stale. Lanes 054 to 059 are all finished. Their verdicts stand as
recorded; none is reinterpreted here.

| Task | Live owner | Base SHA | Owns | Last checkpoint | Component proof | Integration blocker | Successor |
|---|---|---|---|---|---|---|---|
| 054 | none | - | dispatch checking | done | merged | none | - |
| 055 | none | `2cfb3f7` | API pins + companion API test | merged as `13629d9` | `test_api_shapes` 16/16 | `test_companion_api_shapes` red by design | 062 |
| 056 | none | - | reload handling | merged | - | none | - |
| 057 | none | - | case capture | PASS, unacked | `test_case_capture` green | none | 063 |
| 058 | none | - | block port placement | FAIL x3, lane closed | none | superseded | 060 |
| 059 | none | `821b3e7` | port cells free | FAIL x2, work merged as `0bba0db` after hand audit | groups/pack/route green | none | 060 |
| 060 | lane/060 | `routing-recovery-base` | `logic/bp/route.lua`, its tests, `tests/fixtures/routing/` | launched 2026-09-19 | - | - | - |
| 061 | lane/061 | `routing-recovery-base` | `logic/bp/search.lua`, its tests | launched 2026-09-19 | - | - | - |
| 062 | lane/062 | `routing-recovery-base` | companion mod, its tests, runner doc | launched 2026-09-19 | - | - | - |
| 063 | lane/063 | `routing-recovery-base` | five corpus cases, setups | launched 2026-09-19 | - | - | - |

`logic/bp/power.lua` is reserved to the integrator until a handoff; no lane owns it.

### Known red on this base, on purpose

`tests/test_companion_api_shapes.lua` fails for both shapes. It is the merged lane 055 test, and it names the
three companion calls task 062 repairs: `LuaEntity.connect_neighbour`, `LuaGameScript.write_file` and, on 2.1,
`LuaEntity.fluidbox`. Lane gates use focused tests, never `sh tests/run.sh`, while this stands.

### Ready follow-ons

- Remaining corpus partition: unsupported categories, connected poles, bottleneck handling, grid and beacon
  improvement, the 100-machine 30-step boundary. Exact non-overlapping case directories, F's setup pattern.
- Engine collection package: after 062, candidate and companion archives from one committed tree, their hashes,
  per-case commands and output locations.

## Board, 2026-09-20, host legalcopilot-dev

HEAD `249ae51`. Suite **3074 cases, 3074 passed, 0 failed**. On `docs/tasks/058_reproducer.lua` the validator
rejects nothing, routing succeeds once, and the run is terminal in 4.78 s on `BP_FAIL_SEARCH_BUDGET` with no
incumbent after a single grid trial.

Merged this round: 055 API pins, 059 rotated block cells, 060 one expansion budget, 061 grid bound, 062
companion API, 063 corpus chains, 065 independent validator, 067 power semantics, 068 smoke chains, 069
resumable power, 070 port edges, 071 pole wires, 073 underground pairs, 076 splitter footprint, 077 port tile
flow, 078 placed beacon coverage, 079 port never blocks itself, 083 expansion budget for fan-out.

Refused and never merged: 064 and 066 (no-path probe cost), 072 and 075 (collision at the wrong file), 074
(reserved the placed envelope, cost `tests/test_search.lua` 48 cases, reverted), 080 and 081 (corridor candidate
failed validation), 082 (fan-out at the wrong budget, superseded by 083).

Live: `lane/084`, base tag `search-allowance-base` = `249ae51`, task `docs/tasks/084_search_allowance.md`.

Full handoff: `~/.claude/plans/rrc-round-8-handoff-2026-09-20.md`.

## 2026-09-20 afternoon: generation delivers, review `rrc-good-enough-recovery-review-2026-09-20.md` answered

HEAD `93c9d3c`, branch `feat/round-8-blueprints`, never pushed, `main` untouched.

Three acceptance chains reach a delivered, independently validated blueprint through the real generation
service. `docs/tasks/058_reproducer.lua` prints `REPRO state=success`.

```text
sh tests/run.sh                    exit 0; 3134 Lua cases, 0 failed; 81 python tests OK
sh tests/acceptance/run            item 313 ticks, fluid 74 ticks, beacon 194 ticks, all success
docs/tasks/058_reproducer.lua      REPRO state=success stage=done codes=
tests/test_validated_candidate     frozen first candidate validates in 174 operations
```

The python tier had been red since `c50a2bd` (2026-09-19) and was not noticed because only the Lua totals were
read. It is green again, and a captured corpus case now has a state whose rules it meets.

### Findings answered

| Finding | What was wrong | Where it is fixed |
|---|---|---|
| F1 | both smoke cases asserted `state ~= "success"`, and each drove a whole search | `docs/tasks/068_*_smoke.lua` stop at the plan (0.16 s); `tests/acceptance/**` demands success |
| F2 | `search_budget` at the top level of `Generation.start` was dropped | `logic/bp/generation.lua`; `tests/test_generation_controls.lua` reads the value at the Search boundary |
| F3 | every belt, splitter and pipe counted as an electrical consumer | `logic/bp/search.lua` reads `needs_power`; item chain 154 consumers to 17 |
| F4 | "zero validator rejections" was measured where validation never ran | `tests/diag/chain_report.lua` reports validator calls, accepted, rejected and ids from one run |
| F5 | the allowance was one route's expansion count | `logic/bp/search.lua` measures the first candidate and sets one hard ceiling from it |
| F7 | narrow lane tasks preserved a broken end-to-end outcome | repaired end to end here: five cross-module defects, one replayable candidate |

### The five defects that stood between routing and a blueprint

1. Ports were indexed by `id_of`, which never reads `port_id`, so bindings resolved nothing.
2. A port had to be both binding source and binding sink; each port plays one side.
3. Power coverage used the consumer's centre; the engine and the planner use box overlap.
4. A rotated block's port approach was read from the unrotated direction, so a neighbour's belt was reported.
5. Two beacons of one loadout in different blocks shared one id.

### Not done

- No engine evidence. Nothing here has run in Factorio; throughput is unproven.
- Cost, not correctness, is the next target: the item chain takes 313 ticks and a 120 ms worst tick in the
  harness. F6 asks for stage, persistence and status cost to be measured apart before any further tuning.
- Lane 084's work is preserved at tag `lane-084-preserved` (`60906ff`) and was not merged: its own checks
  passed, its fixture gates failed, and a 6000-tick run showed it still ends `pending` with `BP_R_NO_PATH`.

## 2026-09-20 round 9 wave 1: the quality rule and the facts boundary

HEAD `32bb7f9`, tag `round-9-wave-1-green`, branch `feat/round-8-blueprints`, never pushed, `main` untouched.

Answers `~/codex-reviews/rrc-quality-rejection-adversarial-review-2026-09-20.md` and the seven plan reviews that
followed it. Plan rev 8 at `~/.claude/plans/let-s-implement-this-feature-recursive-lighthouse.md`.

```text
sh tests/run.sh                    exit 0; 3358 Lua cases, 0 failed; 97 python tests OK
sh tests/acceptance/run            3 chains success + gate digest 4 cases, 0 failed
test_generation_boundary_rules     20 cases, 0 failed, both branch shapes
058_reproducer.lua                 REPRO state=success stage=done codes=
tools/handoff.sh                   pass; 3376 cases inside each extracted package
```

### The two reported defects

- `preflight.lua:380` asked whether a module's quality effect was non-zero. A speed module's effect is `-0.25`,
  so an ordinary sheet was refused as quality-changing production. One shared rule now answers three separate
  questions in `logic/bp/quality_policy.lua`, and every active machine needs a receiver decision.
- No recipe or receiver facts ever reached the checker, so a chance-based product passed as supported. The
  catalog now projects them, and thin facts are `BP_REJ_PROTOTYPE_FACTS_MISSING`.

Probe on the player's own export, current code: 11 reasons, all `BP_REJ_PROTOTYPE_FACTS_MISSING`, zero
`BP_REJ_QUALITY_CHANGING`. That export predates the projection; enrichment is lane 094.

### Lanes

085 PASS 855 s, 086 PASS 522 s, 087 PASS 761 s, 088 PASS 956 s, 090 PASS 1691 s, 089 engine-timeout 2900 s with
work committed and audited green. Six dispatched in parallel, one background shell each.

### Caught by hand audit, missed by lane gates

1. Lane 087 wrote `forbids_speed_beacon = has_quality_module or speed_beacon > 0`, which would have made
   `validate.lua:639-642` refuse every ordinary speed-beacon factory. Corrected, pinned by case `BR10`.
2. Two suite cases asserted "this is a source checkout" and could never hold inside a package, so the first
   real handoff refused. Both now assert one rule in either tree.
3. The handoff command deleted the archives it verified. `RRC_HANDOFF_KEEP_ARCHIVES` keeps exactly those bytes.

### Delivered

```text
RRC-Fork_1.1.51_factorio-2.0-test.zip  24773c53f56a556db10404c1f4f4844acf1ccc666779e7a85f528c4a1db3c03e
RRC-Fork_1.1.52_factorio-2.1-test.zip  f3cbb941287df9bcf05677ba576680f451f6ebe9d0bf7436d9a8b26c521f67ce
```

### Not done

M3 stays blocked: no Factorio on this host, 1 accepted golden case, 0 engine observations. Wave 2 (091 real-data
acceptance, 092 capacity model, 093 export facts, 094 the reported chain to delivery, 095 publication freeze) is
dispatched from `round-9-wave-1-green`.
